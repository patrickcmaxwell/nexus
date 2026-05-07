import Foundation
import Combine

// LumenArenaHealth
//
// Tiny singleton that holds the count of errored Arena connections. Lets
// the Console tab picker render a red badge on the Arena tab without
// every consumer having to fetch the connection list themselves.
//
// Updated by:
//   - LumenArenaView whenever it loads or refreshes (authoritative)
//   - A background poller every 90s while the Console window is open
//
// Read by:
//   - LumenConsoleWindow's tabPicker — adds a dot when erroredCount > 0
//   - Anywhere else that wants a glanceable health signal (menu bar,
//     orb window status, etc.)

@MainActor
final class LumenArenaHealth: ObservableObject {
    static let shared = LumenArenaHealth()

    @Published private(set) var erroredCount: Int = 0
    @Published private(set) var totalCount: Int = 0
    @Published private(set) var lastChecked: Date? = nil

    private var pollTask: Task<Void, Never>? = nil

    /// Authoritative update from LumenArenaView. Pass the connection list
    /// you just fetched; we count errored rows + cache the total.
    func update<C: Sequence>(connections: C) where C.Element == LumenArenaView.Connection {
        let arr = Array(connections)
        erroredCount = arr.filter { $0.status == "errored" }.count
        totalCount = arr.count
        lastChecked = Date()
    }

    /// Start a background poll (every 90s). Idempotent — safe to call
    /// multiple times. Stops on app teardown.
    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            // Tick once immediately for the initial value
            await self?.tick()
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 90_000_000_000)
                if Task.isCancelled { break }
                await self.tick()
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func tick() async {
        let base = LumenAPIManager.shared.nexusBase
        guard let url = URL(string: "\(base)/api/arena/connections") else { return }
        var req = URLRequest(url: url, timeoutInterval: 8)
        if let cookie = LumenAPIManager.shared.sessionCookie {
            req.setValue("nx_session=\(cookie)", forHTTPHeaderField: "Cookie")
            req.setValue("Bearer \(cookie)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            // Parse minimally — we only need status counts.
            struct Payload: Decodable {
                struct Conn: Decodable { let status: String }
                let connections: [Conn]
            }
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            erroredCount = payload.connections.filter { $0.status == "errored" }.count
            totalCount = payload.connections.count
            lastChecked = Date()
        } catch {
            // Network blip — don't blow away the last known good count.
        }
    }
}
