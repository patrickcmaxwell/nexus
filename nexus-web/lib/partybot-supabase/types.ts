// Mirrors the bots schema in partybot's Supabase. Source of truth lives at
// /Users/shadow/code/ops/v0-partybot5000-concept-discussion/components/dashboard/types.ts
// and the migrations in that repo's scripts/. Kept narrow on purpose — we
// only pull what the cockpit needs.

export type PartybotBot = {
  id: string
  user_id: string
  bot_name: string
  archetype: string
  archetype_label: string
  tag: string
  color: string
  sass_mode: boolean
  body_type: string | null
  bio: string | null
  custom_prompt: string | null
  rules: string | null
  friend_rules: string | null
  is_public: boolean | null
  is_primary: boolean | null
  is_owner_canonical?: boolean | null  // added by partybot migration 020
  created_at: string
  updated_at: string
}

export type PartybotDevice = {
  id: string
  user_id: string
  label: string
  device_fingerprint: string
  paired_at: string
  last_seen_at: string | null
  last_consciousness_hash: string | null
  revoked_at: string | null
}

// Append-only log of every push from laptop CLI to Pi. Migration:
// /Users/shadow/code/ops/v0-partybot5000-concept-discussion/scripts/030_push_log.sql
export type PushLogEntry = {
  id: string
  user_id: string
  bot_id: string | null
  host: string
  port: number
  bundle_hash: string
  status: "ok" | "not_modified" | "error" | "dry_run"
  http_status: number | null
  error_msg: string | null
  source: "cli" | "cockpit"
  pushed_at: string
}

// Derived from push_log: distinct hosts that have received a push in the
// window, with their latest activity. Computed in the page, not stored.
export type ActiveDevice = {
  host: string
  port: number
  last_push_at: string
  last_bundle_hash: string
  last_status: PushLogEntry["status"]
  push_count: number
  latest_bot_id: string | null
}
