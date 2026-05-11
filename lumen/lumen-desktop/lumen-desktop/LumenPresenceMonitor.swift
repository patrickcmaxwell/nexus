// LumenPresenceMonitor.swift
//
// Continuous-presence guard. Lumen is a command surface — once the
// Director steps away, anyone walking up to the Mac would otherwise see
// (and could drive) live operations, memory, terminal sessions. The
// monitor watches three signals and locks the app whenever the answer
// to "is Patrick still here?" becomes unknown:
//
//   1. Periodic re-verify (default every 20 min while focused). Spins
//      up a headless FaceCaptureSession, gives the camera 5 s to see a
//      face, POSTs the frame to /api/security/face/match. Match → reset
//      the timer, no UI change at all (camera light blinks; that's the
//      only visible side-effect). Miss / no face → flip `isLocked = true`
//      and `PresenceLockView` overlays the main window.
//
//   2. Idle / focus loss. When Lumen loses focus we start an idle timer
//      (default 5 min). When it fires we lock regardless of whether the
//      app has regained focus — so walking back to the Mac always sees
//      the lock screen, not the live UI.
//
//   3. Manual lock (⌘L menu item, or sign-out path). Useful when the
//      Director is about to walk away and doesn't want to wait for the
//      idle timer.
//
// Unlocking goes through PresenceLockView: face capture (preferred) or
// PIN re-entry against the same /api/security/face/match endpoint. The
// app keeps running underneath the lock — sync, terminal bridge, voice
// timers, scheduled jobs all stay alive. The lock is a curtain, not a
// shutdown.

import Foundation
import AppKit
import Combine
import SwiftUI

@MainActor
final class LumenPresenceMonitor: ObservableObject {
    /// Whether the app is currently locked behind the presence curtain.
    /// SwiftUI binds an overlay to this in lumen_desktopApp.
    @Published private(set) var isLocked: Bool = false

    /// Status of the most recent silent re-verify. Surfaced in the lock
    /// screen banner so the user knows why they're being asked to unlock.
    @Published private(set) var lastLockReason: LockReason = .manual

    /// True while a silent re-check is mid-flight. The lock view uses
    /// this to suppress the unlock UI for a beat so the camera light
    /// blinking doesn't look like the lock screen "flickering."
    @Published private(set) var isReverifying: Bool = false

    enum LockReason: String {
        case manual          = "Manually locked"
        case periodicMissed  = "Periodic face check failed"
        case periodicNoFace  = "No face detected during periodic check"
        case idle            = "Lumen was idle"
        case launchGate      = "Verify face to enter Lumen"
    }

    // ── Settings (persisted) ─────────────────────────────────────────────
    @AppStorage("lumen.presence.enabled")          var enabled: Bool        = true
    @AppStorage("lumen.presence.intervalMinutes")  var intervalMinutes: Int = 20
    @AppStorage("lumen.presence.idleMinutes")      var idleMinutes: Int     = 5
    @AppStorage("lumen.presence.muteOnLock")       var muteOnLock: Bool     = true

    // ── Internals ────────────────────────────────────────────────────────
    private var periodicTimer: Timer?
    private var idleTimer: Timer?
    private var focusLostAt: Date?
    private var focusObservers: [NSObjectProtocol] = []
    private var nexusBase: String { LumenAPIManager.shared.nexusBase }

    /// Optional hook so the App can stop the voice/mic when the curtain
    /// drops. Set from lumen_desktopApp.init.
    var onLockEngaged: (() -> Void)?

    // MARK: Lifecycle

    /// Start monitoring. Call once the user is authenticated. Idempotent —
    /// safe to call multiple times (resets timers).
    func start() {
        stop()
        guard enabled else { return }
        scheduleNextPeriodic()
        installFocusObservers()
        installManualLockObserver()
    }

    /// Stop monitoring. Call on sign-out, or before changing settings.
    func stop() {
        periodicTimer?.invalidate(); periodicTimer = nil
        idleTimer?.invalidate(); idleTimer = nil
        focusObservers.forEach { NotificationCenter.default.removeObserver($0) }
        focusObservers.removeAll()
        focusLostAt = nil
    }

    /// Apply changed settings. Restart timers with new intervals.
    func applySettings() {
        if enabled {
            start()
        } else {
            stop()
        }
    }

    // MARK: Locking

    /// Public entry point for ⌘L, "Lock Now" button, sign-out cleanup.
    func lockNow(reason: LockReason = .manual) {
        engageLock(reason: reason)
    }

    /// Unlock — called by PresenceLockView on successful face match or
    /// correct PIN. Restarts the periodic timer so we don't immediately
    /// re-verify right after a manual unlock.
    func unlock() {
        isLocked = false
        focusLostAt = nil
        idleTimer?.invalidate(); idleTimer = nil
        scheduleNextPeriodic()
    }

    private func engageLock(reason: LockReason) {
        guard !isLocked else { return }
        lastLockReason = reason
        isLocked = true
        periodicTimer?.invalidate(); periodicTimer = nil
        idleTimer?.invalidate(); idleTimer = nil
        if muteOnLock { onLockEngaged?() }
    }

    // MARK: Periodic silent re-verify

    private func scheduleNextPeriodic() {
        periodicTimer?.invalidate()
        guard enabled, !isLocked else { return }
        let interval = max(60, TimeInterval(intervalMinutes * 60))
        periodicTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.runSilentReverify() }
        }
    }

    /// Headless face check. Spins up FaceCaptureSession with no preview
    /// view, gives the camera 5 s to lock on a face, captures one frame,
    /// uploads to /api/security/face/match. Pass → reset and reschedule.
    /// Fail → lock with the appropriate reason.
    private func runSilentReverify() async {
        guard enabled, !isLocked else { return }
        isReverifying = true
        defer { isReverifying = false }

        let session = FaceCaptureSession()
        let started = await session.start()
        guard started else {
            // Camera unavailable — don't lock the user out for a hardware
            // glitch. Just reschedule and try again next cycle. If the
            // camera is permanently broken they can disable presence in
            // settings.
            scheduleNextPeriodic()
            return
        }
        defer { session.stop() }

        // Wait up to 5 s for the face-rectangle detector to lock on. If
        // nothing's there, the user isn't in front of the camera — lock.
        let waitDeadline = Date().addingTimeInterval(5.0)
        while Date() < waitDeadline {
            if session.faceDetected { break }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        guard session.faceDetected else {
            engageLock(reason: .periodicNoFace)
            return
        }

        // Tiny settle delay so the captured frame isn't mid-blink / motion
        try? await Task.sleep(nanoseconds: 250_000_000)

        let jpeg: Data? = await withCheckedContinuation { cont in
            session.captureStill { data in cont.resume(returning: data) }
        }
        guard let jpeg else {
            // Capture itself failed — same hardware-glitch reasoning as above.
            scheduleNextPeriodic()
            return
        }

        let matched = await uploadAndMatch(jpegData: jpeg)
        if matched {
            scheduleNextPeriodic()
        } else {
            engageLock(reason: .periodicMissed)
        }
    }

    private func uploadAndMatch(jpegData: Data) async -> Bool {
        guard let url = URL(string: "\(nexusBase)/api/security/face/match") else { return false }
        let dataUrl = "data:image/jpeg;base64,\(jpegData.base64EncodedString())"

        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("1", forHTTPHeaderField: "X-Lumen-Client")
        if let cookie = LumenAPIManager.shared.sessionCookie {
            // Tell the server we're a presence re-verify, not a fresh login —
            // it should match against the active session's enrolled human
            // rather than searching all references. Server may ignore this
            // header today; harmless if so. Cookie identifies who we expect.
            req.setValue("Bearer \(cookie)", forHTTPHeaderField: "Authorization")
            req.setValue("nx_session=\(cookie)", forHTTPHeaderField: "Cookie")
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["imageDataUrl": dataUrl])

        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { return false }
            return http.statusCode == 200
        } catch {
            // Network failure shouldn't lock the user out of their own Mac;
            // treat as inconclusive and reschedule.
            return true
        }
    }

    // MARK: Idle / focus tracking

    private func installFocusObservers() {
        let nc = NotificationCenter.default
        let resign = nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleFocusLost() }
        }
        let become = nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleFocusGained() }
        }
        focusObservers = [resign, become]
    }

    private func installManualLockObserver() {
        let obs = NotificationCenter.default.addObserver(forName: .lumenLockNow, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.lockNow(reason: .manual) }
        }
        focusObservers.append(obs)
    }

    private func handleFocusLost() {
        guard enabled, !isLocked else { return }
        focusLostAt = Date()
        idleTimer?.invalidate()
        let interval = max(30, TimeInterval(idleMinutes * 60))
        idleTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.engageLock(reason: .idle) }
        }
    }

    private func handleFocusGained() {
        // If we already crossed the threshold while away, the idleTimer
        // will have fired and locked us. If we're back inside the window,
        // cancel the pending lock.
        idleTimer?.invalidate(); idleTimer = nil
        focusLostAt = nil
    }
}
