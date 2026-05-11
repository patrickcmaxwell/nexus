// WatchPhoneBridge.swift
// Watch side of the Watch ↔ Phone WCSession bridge. Sends a transcript to
// the iPhone and awaits Eve's reply text. The phone (PhoneWatchBridge.swift)
// is the only side that talks to nexus-web.

import Foundation
import Combine
import WatchConnectivity

@MainActor
final class WatchPhoneBridge: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchPhoneBridge()

    @Published var phoneReachable: Bool = false
    @Published var activated: Bool = false

    enum BridgeError: Error {
        case unreachable
        case replyError(String)
        case noActivation
    }

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
            self.activated      = (activationState == .activated)
            self.phoneReachable = session.isReachable
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.phoneReachable = session.isReachable }
    }

    /// Sends transcript to the iPhone and awaits Eve's reply. If the phone
    /// is unreachable, queues via `transferUserInfo` (delivery when phone
    /// wakes) and throws so the UI can show "phone unreachable".
    func askPhone(_ transcript: String) async throws -> String {
        let session = WCSession.default
        guard session.activationState == .activated else { throw BridgeError.noActivation }

        if !session.isReachable {
            session.transferUserInfo(["ask": transcript])
            throw BridgeError.unreachable
        }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            session.sendMessage(["ask": transcript], replyHandler: { reply in
                if let err = reply["error"] as? String {
                    cont.resume(throwing: BridgeError.replyError(err))
                } else if let text = reply["reply"] as? String {
                    cont.resume(returning: text)
                } else {
                    cont.resume(throwing: BridgeError.replyError("empty reply"))
                }
            }, errorHandler: { error in
                cont.resume(throwing: error)
            })
        }
    }
}
