// EveOnDeviceBrain.swift
// Third brain tier: Apple's on-device Foundation Model. Runs entirely on
// the Neural Engine, never hits the network. Used as a true offline
// fallback when both /api/eve (cloud Grok) and /api/eve/local (home
// Ollama) are unreachable — say, on a plane.
//
// Wrapped behind `#if canImport(FoundationModels)` so the app still builds
// on Xcode setups that don't have the SDK headers, and behind a runtime
// availability check on `SystemLanguageModel` so it gracefully reports
// "unavailable" on devices that don't have Apple Intelligence enabled
// (older A-series chips, or Intelligence not yet activated by the user).
//
// Persona: same calm-Eve system prompt the cloud paths use, kept short
// because the on-device model has a smaller context window than Grok.

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum EveOnDeviceBrain {
    /// True when Apple Intelligence is installed AND enabled on this
    /// device. Use this to gate UI: don't show the "On-Device" brain pill
    /// if it isn't available.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        return false
        #else
        return false
        #endif
    }

    /// Human-readable status — "available", "unavailable: device not
    /// eligible", "unavailable: needs to download." Use in Settings.
    static var statusDescription: String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return "available"
            case .unavailable(.deviceNotEligible):
                return "unavailable — this device doesn't support Apple Intelligence"
            case .unavailable(.appleIntelligenceNotEnabled):
                return "unavailable — turn on Apple Intelligence in Settings"
            case .unavailable(.modelNotReady):
                return "unavailable — model is still downloading"
            case .unavailable(let other):
                return "unavailable — \(String(describing: other))"
            }
        }
        return "unavailable on this iOS version"
        #else
        return "unavailable in this build"
        #endif
    }

    /// Fire a single user message at the on-device model and return the
    /// reply. Same signature shape as the other brain tiers so the voice
    /// manager can swap it in without restructuring its call site.
    static func ask(_ userMessage: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            guard isAvailable else { throw OnDeviceError.unavailable }
            let system = """
            You are Eve, the private AI command intelligence of Patrick \
            Maxwell. Address Patrick by his first name — never sir or \
            director. Be direct, calm, efficient. Dry wit permitted. \
            Short sentences — you are speaking aloud, not writing a report.
            """
            let session = LanguageModelSession(instructions: system)
            let response = try await session.respond(to: userMessage)
            return response.content
        }
        throw OnDeviceError.unavailable
        #else
        throw OnDeviceError.unavailable
        #endif
    }

    enum OnDeviceError: Error { case unavailable }
}
