// EveMemoryManager.swift
// Loads the correct memory files based on who is logged in
//
// Setup: Add eve-base.md, eve-private.md, and eve-shared.md
// to your nexus-ios/ Xcode target (make sure they're in the bundle)

import Foundation

class EveMemoryManager {
    static let shared = EveMemoryManager()

    private init() {}

    /// Returns the correct system prompt for Eve based on the current user
    func loadEveContext(for userId: String) async -> String {
        let base = loadFile(named: "eve-base") ?? ""

        if userId.lowercased() == "patrick" {
            let privateMemory = loadFile(named: "eve-private") ?? ""
            return base + "\n\n" + privateMemory
        } else {
            let sharedMemory = loadFile(named: "eve-shared") ?? ""
            return base + "\n\n" + sharedMemory
        }
    }

    private func loadFile(named name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "md") else {
            print("⚠️ Memory file not found: \(name).md")
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

// Usage:
// let context = await EveMemoryManager.shared.loadEveContext(for: currentUserId)
// Pass `context` as the system prompt to your LLM call
