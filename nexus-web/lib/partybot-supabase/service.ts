import { createClient, type SupabaseClient } from "@supabase/supabase-js"

// Partybot lives in its own Supabase project. The cockpit reads it directly
// via a service-role client (Arena is the trusted writer for the owner).
//
// Env vars (server-only, never NEXT_PUBLIC_):
//   PARTYBOT_SUPABASE_URL
//   PARTYBOT_SUPABASE_SERVICE_ROLE_KEY
//
// Returns null when either env is missing instead of throwing — lets the
// cockpit ship behind a feature flag and render a "configure to activate"
// empty state until you wire the keys.

let _cached: SupabaseClient | null | undefined

export function createPartybotServiceClient(): SupabaseClient | null {
  if (_cached !== undefined) return _cached
  const url = process.env.PARTYBOT_SUPABASE_URL
  const key = process.env.PARTYBOT_SUPABASE_SERVICE_ROLE_KEY
  if (!url || !key) {
    _cached = null
    return null
  }
  _cached = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } })
  return _cached
}

export function partybotConfigured(): boolean {
  return Boolean(process.env.PARTYBOT_SUPABASE_URL && process.env.PARTYBOT_SUPABASE_SERVICE_ROLE_KEY)
}
