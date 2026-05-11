// PhoneWatchBridge.swift
// iPhone side of the Watch ↔ Phone bridge. Receives transcripts from the
// Watch via WCSession, forwards them to /api/eve through NexusAPIClient,
// and replies with Eve's text. The phone holds the auth + does all network
// I/O — the Watch never sees a session token or hits nexus-web directly.

import Foundation
import Combine
import WatchConnectivity

@MainActor
final class PhoneWatchBridge: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = PhoneWatchBridge()

    @Published var watchPaired: Bool = false
    @Published var watchReachable: Bool = false
    @Published var lastWatchMessage: String = ""

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        Task { @MainActor in
            self.watchPaired    = session.isPaired
            self.watchReachable = session.isReachable
        }
    }

    // iOS-only delegate methods. Required to recover the session if the
    // user pairs a different watch later.
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
    func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.watchPaired = session.isPaired }
    }
    func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.watchReachable = session.isReachable }
    }

    /// Watch sends `["ask": "<transcript>"]` and expects a reply
    /// `["reply": "<eve text>"]` (or `["error": "<reason>"]`). Replies must
    /// happen synchronously on the WCSession thread, so we use the legacy
    /// dispatch wrapper to bridge to async.
    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        guard let transcript = message["ask"] as? String, !transcript.isEmpty else {
            replyHandler(["error": "empty"])
            return
        }
        Task {
            await self.handleWatchAsk(transcript: transcript, replyHandler: replyHandler)
        }
    }

    /// Background variant — Watch can also queue messages via
    /// `transferUserInfo` when phone is asleep. We surface them as fire-and-
    /// forget asks; reply isn't possible here, just acknowledge by storing
    /// the latest transcript so the iPhone UI shows what was asked.
    nonisolated func session(_ session: WCSession,
                             didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let transcript = userInfo["ask"] as? String, !transcript.isEmpty else { return }
        Task { await self.handleWatchAsk(transcript: transcript, replyHandler: nil) }
    }

    private func handleWatchAsk(transcript: String,
                                replyHandler: (([String: Any]) -> Void)?) async {
        await MainActor.run { self.lastWatchMessage = transcript }
        do {
            let result = try await NexusAPIClient.shared.askEve(message: transcript)
            replyHandler?(["reply": result.content])
        } catch NexusAPIClient.APIError.unauthorized {
            replyHandler?(["error": "Sign in on the iPhone first."])
        } catch {
            replyHandler?(["error": "Brain unreachable."])
        }
    }
}
