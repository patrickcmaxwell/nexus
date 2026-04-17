// SupabaseManager.swift
// Nexus iOS — connects to the same Supabase project as nexus-web
//
// Setup:
// 1. File → Add Package Dependency → https://github.com/supabase/supabase-swift
// 2. Replace YOUR_PROJECT_URL and YOUR_ANON_KEY below

import Supabase
import Foundation

class SupabaseManager {
    static let shared = SupabaseManager()

    let client: SupabaseClient

    private init() {
        self.client = SupabaseClient(
            supabaseURL: URL(string: "https://YOUR_PROJECT_URL.supabase.co")!,
            supabaseKey: "YOUR_ANON_KEY_HERE"
        )
    }

    /// Quick connection test — call on app launch
    func testConnection() async {
        do {
            let _: [String: String] = try await client
                .from("conversations")
                .select()
                .limit(1)
                .execute()
                .value
            print("✅ Supabase connected")
        } catch {
            print("❌ Supabase connection failed: \(error)")
        }
    }
}
