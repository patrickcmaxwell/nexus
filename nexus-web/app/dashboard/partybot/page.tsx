import { redirect } from "next/navigation"
import { getActiveHuman } from "@/lib/auth/session"
import { createPartybotServiceClient } from "@/lib/partybot-supabase/service"
import type { PartybotBot, PartybotDevice, PushLogEntry, ActiveDevice } from "@/lib/partybot-supabase/types"
import PartybotPanel from "@/components/dashboard/PartybotPanel"

export const dynamic = "force-dynamic"

export default async function PartybotPage() {
  const me = await getActiveHuman()
  if (!me) redirect("/auth/login")
  if (!me.isOwner) redirect("/dashboard")

  const supabase = createPartybotServiceClient()

  if (!supabase) {
    return (
      <PartybotPanel
        configured={false}
        initialBots={[]}
        initialDevices={[]}
        initialActiveDevices={[]}
        initialRecentPushes={[]}
      />
    )
  }

  // Bots, raw paired devices, and recent push log in parallel. Partybot RLS
  // is keyed to its own auth.uid; we're service-role here so we see everything
  // in that project. Correct for a single-owner setup; if we multi-tenant later
  // we filter on partybot's user_id mapped from the Nexus identity.
  const [botsRes, devicesRes, pushesRes] = await Promise.all([
    supabase
      .from("bots")
      .select("id, user_id, bot_name, archetype, archetype_label, tag, color, sass_mode, body_type, bio, custom_prompt, rules, friend_rules, is_public, is_primary, is_owner_canonical, created_at, updated_at")
      .order("updated_at", { ascending: false }),
    supabase
      .from("device_registrations")
      .select("id, user_id, label, device_fingerprint, paired_at, last_seen_at, last_consciousness_hash, revoked_at")
      .is("revoked_at", null)
      .order("paired_at", { ascending: false }),
    supabase
      .from("push_log")
      .select("id, user_id, bot_id, host, port, bundle_hash, status, http_status, error_msg, source, pushed_at")
      .gte("pushed_at", new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString())
      .order("pushed_at", { ascending: false })
      .limit(200),
  ])

  // Some installs won't have run the 030 migration yet; treat a missing table
  // as "no pushes" rather than crashing the page.
  const pushes: PushLogEntry[] = (pushesRes.error ? [] : (pushesRes.data ?? [])) as PushLogEntry[]
  const activeDevices = deriveActiveDevices(pushes)

  const fetchError =
    botsRes.error?.message ||
    devicesRes.error?.message ||
    (pushesRes.error && !isMissingTable(pushesRes.error.message) ? pushesRes.error.message : null)

  return (
    <PartybotPanel
      configured={true}
      initialBots={(botsRes.data ?? []) as PartybotBot[]}
      initialDevices={(devicesRes.data ?? []) as PartybotDevice[]}
      initialActiveDevices={activeDevices}
      initialRecentPushes={pushes.slice(0, 25)}
      fetchError={fetchError}
    />
  )
}

function deriveActiveDevices(pushes: PushLogEntry[]): ActiveDevice[] {
  const byHost = new Map<string, ActiveDevice>()
  // pushes already sorted desc; first hit per host is the latest.
  for (const p of pushes) {
    const key = `${p.host}:${p.port}`
    const existing = byHost.get(key)
    if (!existing) {
      byHost.set(key, {
        host: p.host,
        port: p.port,
        last_push_at: p.pushed_at,
        last_bundle_hash: p.bundle_hash,
        last_status: p.status,
        push_count: 1,
        latest_bot_id: p.bot_id,
      })
    } else {
      existing.push_count++
    }
  }
  return [...byHost.values()].sort((a, b) => b.last_push_at.localeCompare(a.last_push_at))
}

function isMissingTable(msg: string): boolean {
  // Postgres surface for "relation does not exist" — graceful when migration
  // 030 hasn't been applied yet.
  return /relation\s+"?public\.push_log"?\s+does not exist/i.test(msg) ||
         /could not find the table 'public\.push_log'/i.test(msg)
}
