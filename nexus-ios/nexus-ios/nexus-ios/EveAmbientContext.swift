// EveAmbientContext.swift
// Background context that Eve can fold into briefings without the user
// having to ask. Three sensors, one published struct:
//
//   - CoreLocation (significant-change only, battery-friendly)
//   - WeatherKit   (current conditions for that location)
//   - CoreMotion   (driving/walking/cycling activity classification)
//
// Privacy posture: every signal stays on-device unless Eve explicitly
// includes it in a /api/eve message. CLLocationManager uses
// `requestWhenInUseAuthorization` plus `startMonitoringSignificantLocation
// Changes` — no continuous tracking, no background-location entitlement,
// no draining the battery. CoreMotion needs only the privacy descriptor
// in Info.plist (NSMotionUsageDescription). WeatherKit requires the user
// to be in an Apple Developer account with WeatherKit capability — the
// Foundation API works without an explicit key when the entitlement is
// active.

import Foundation
import Combine
import CoreLocation
import CoreMotion
#if canImport(WeatherKit)
import WeatherKit
#endif

@MainActor
final class EveAmbientContext: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = EveAmbientContext()

    /// Compact one-line phrase: "57°F overcast · home · driving". Empty
    /// when nothing is known yet. Briefing UI / App Intent dialog reads
    /// this and prepends to whatever Eve was about to say.
    @Published var contextLine: String = ""

    @Published var locationLabel: String = ""        // "home" / "office" / city name fallback
    @Published var weatherLabel: String = ""         // "57°F overcast"
    @Published var activityLabel: String = ""        // "driving" / "walking" / ""

    private let locationManager = CLLocationManager()
    private let motionManager   = CMMotionActivityManager()

    private override init() {
        super.init()
        locationManager.delegate = self
        // Significant-change is the right battery posture for a calm
        // briefing companion. Granular tracking would be wasted on a
        // "where am I roughly" use case.
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Start collecting ambient context. Call once on app launch *after*
    /// the user is authenticated — there's no point sampling weather for
    /// the PIN screen.
    func start() {
        // Location auth ladder: only ask for "when in use." We never ask
        // for "always" because we don't need it — significant-change wakes
        // briefly without the always grant.
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startMonitoringSignificantLocationChanges()
            locationManager.requestLocation()
        default:
            break
        }

        // Motion activity — needs NSMotionUsageDescription set in Info.plist.
        // Without it, CoreMotion silently fails on iOS 16+. We log so it's
        // visible in Xcode console rather than mysteriously missing.
        guard CMMotionActivityManager.isActivityAvailable() else {
            NSLog("[nexus-ambient] CoreMotion unavailable on this device")
            return
        }
        motionManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self, let a = activity else { return }
            let label: String
            if a.automotive { label = "driving" }
            else if a.cycling { label = "cycling" }
            else if a.running { label = "running" }
            else if a.walking { label = "walking" }
            else if a.stationary { label = "" }   // boring, suppress
            else { label = "" }
            self.activityLabel = label
            self.recompute()
        }
    }

    /// Convenience: are we driving right now? Voice tab uses this to hide
    /// the typed composer and bias to talk-only when the user is in motion.
    var isDriving: Bool { activityLabel == "driving" }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.startMonitoringSignificantLocationChanges()
                manager.requestLocation()
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { await self.handleLocation(loc) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        NSLog("[nexus-ambient] location error: %@", error.localizedDescription)
    }

    // MARK: - Private

    /// Reverse-geocode the location into a human-readable label, then
    /// fetch a one-line weather summary. Both are best-effort.
    private func handleLocation(_ loc: CLLocation) async {
        let geocoder = CLGeocoder()
        if let placemarks = try? await geocoder.reverseGeocodeLocation(loc),
           let p = placemarks.first {
            // Heuristic friendly label: locality > sublocality > name.
            // The user can rename via app settings later (out of scope tonight).
            let label = p.locality ?? p.subLocality ?? p.name ?? ""
            await MainActor.run { self.locationLabel = label }
        }

        #if canImport(WeatherKit)
        do {
            let weather = try await WeatherService.shared.weather(for: loc)
            let cur = weather.currentWeather
            let f = MeasurementFormatter()
            f.unitOptions = .temperatureWithoutUnit
            f.numberFormatter.maximumFractionDigits = 0
            let temp = f.string(from: cur.temperature)
            let cond = cur.condition.description.lowercased()
            await MainActor.run { self.weatherLabel = "\(temp)°F \(cond)" }
        } catch {
            NSLog("[nexus-ambient] weather error: %@", error.localizedDescription)
        }
        #endif

        recompute()
    }

    private func recompute() {
        let parts = [weatherLabel, locationLabel, activityLabel].filter { !$0.isEmpty }
        contextLine = parts.joined(separator: " · ")
    }
}
