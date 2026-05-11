// EveBiometrics.swift
// LocalAuthentication wrapper for Face ID / Touch ID. Used to gate access
// to the cached Nexus session: once the user has signed in via PIN or
// face-WebView, we keep the sessionId in Keychain and only re-prompt on
// fresh launches OR after the lock interval expires. The biometric
// challenge is the *unlock*, not the auth itself — Apple's biometrics
// never leave the Secure Enclave, and the nexus-web server doesn't see
// any biometric data.
//
// Why the toggle pattern: some users won't have biometrics enrolled
// (older devices, deliberately disabled, simulator without registered
// face). For them, `isAvailable` is false and the app silently falls back
// to PIN. Never show a "set up Face ID" pestering UI — that's the OS's job.

import Foundation
import LocalAuthentication

@MainActor
final class EveBiometrics {
    static let shared = EveBiometrics()
    private init() {}

    /// True when this device has biometrics enrolled and available.
    /// Returns false on simulator unless Features → Face ID → Enrolled.
    var isAvailable: Bool {
        var error: NSError?
        let canEvaluate = LAContext().canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        )
        return canEvaluate
    }

    /// Display name of the available biometric, or empty when none.
    /// Used by Settings to show "Use Face ID to unlock" / "Use Touch ID."
    var biometryName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID:        return "Face ID"
        case .touchID:       return "Touch ID"
        case .opticID:       return "Optic ID"
        default:             return ""
        }
    }

    /// Prompt the user for biometric verification. The reason string is
    /// shown in the system dialog; keep it short and human.
    /// Returns true on success, false on cancel/fallback. Throws only on
    /// hard configuration errors (no biometry available, etc.) — caller
    /// should treat throws as "fall back to PIN."
    func authenticate(reason: String = "Unlock Nexus") async throws -> Bool {
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "Use PIN"
        return try await ctx.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: reason
        )
    }

    // MARK: - Lock state

    /// User-controlled toggle (Settings) — defaults to ON when biometrics
    /// are available. Persisted in UserDefaults so the choice survives
    /// reinstalls only if the user has iCloud Backup; otherwise resets to
    /// ON on a fresh install (we want it on by default).
    private static let toggleKey = "nexus.biometrics.enabled"
    var isUnlockEnabled: Bool {
        // Opt-in. Default OFF so the biometric prompt never gets in the
        // way of fresh sign-in flows (especially on the simulator, where
        // Face ID isn't enrolled and the prompt would just confuse).
        // User flips this in Settings → "Use Face ID to unlock."
        get { UserDefaults.standard.bool(forKey: Self.toggleKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.toggleKey) }
    }

    /// True when the app should show the biometric prompt on launch:
    /// session is cached AND the user has unlock enabled AND biometrics
    /// are available.
    var shouldUnlockOnLaunch: Bool {
        isUnlockEnabled && isAvailable && (NexusAPIClient.shared.sessionId?.isEmpty == false)
    }
}
