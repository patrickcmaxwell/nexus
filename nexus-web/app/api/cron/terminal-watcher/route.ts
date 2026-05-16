// /api/cron/terminal-watcher
//
// Every minute (Vercel cron): scan `terminal_sessions` for active rows
// the watcher hasn't already classified at their current snapshot, run
// the heuristic classifier, dedup against `terminal_watch_state`, and
// fire a push notification on new alert conditions.
//
// Auth: same cron-secret pattern as /api/schedules/runner. Vercel adds
// `Authorization: Bearer ${CRON_SECRET}` automatically when invoking
// via the dashboard cron table; the route also accepts an internal
// `x-internal-cron: 1` header for explicit manual triggers.
//
// Why every minute, not faster: Lumen heartbeats every 30s, so snapshot
// freshness ceils at ~30s anyway. Minute granularity matches the cron
// runner's cadence and keeps Supabase row counts sane.

import { NextRequest, NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { classify, snapshotHash, type AlertKind } from "@/lib/terminal/classify"
import { sendPushToAuthUser } from "@/lib/push/dispatch"

export const runtime = "nodejs"
export const maxDuration = 30
export const dynamic = "force-dynamic"

// How long to suppress the same (kind, signature) for the same session
// after firing. Pages should be "you got blocked" once, not every minute
// until you notice. After this elapses we'll re-fire if the condition
// still holds — a way to recover from "user dismissed but forgot about it."
const ALERT_COOLDOWN_MS = 30 * 60 * 1000

interface SessionRow {
  id: string
  user_id: string
  title: string | null
  folder: string
  mac_label: string | null
  status: string
  last_snapshot: string | null
  last_snapshot_at: string | null
  last_heartbeat_at: string | null
}

interface WatchStateRow {
  session_id: string
  last_evaluated_hash: string | null
  last_alert_kind: string | null
  last_alert_signature: string | null
  last_alert_at: string | null
  repeat_count: number
}

export async function GET(req: NextRequest) {
  return run(req)
}

// POST so we can trigger manually with `curl -X POST` while debugging
// (Vercel cron uses GET).
export async function POST(req: NextRequest) {
  return run(req)
}

async function run(req: NextRequest) {
  const expected = process.env.CRON_SECRET
  if (expected) {
    const auth = req.headers.get("authorization")
    const internal = req.headers.get("x-internal-cron")
    const ok = auth === `Bearer ${expected}` || internal === "1"
    if (!ok) return NextResponse.json({ error: "unauthorized" }, { status: 401 })
  }

  const supabase = createServiceClient()

  // Pull active sessions with a snapshot. We don't bother with sessions
  // that are exited/error/stale — those won't be doing anything new.
  const { data: sessions, error: sessErr } = await supabase
    .from("terminal_sessions")
    .select("id, user_id, title, folder, mac_label, status, last_snapshot, last_snapshot_at, last_heartbeat_at")
    .eq("status", "running")
    .not("last_snapshot", "is", null)
    .returns<SessionRow[]>()
  if (sessErr) {
    return NextResponse.json({ error: sessErr.message }, { status: 500 })
  }

  const rows = sessions ?? []
  if (rows.length === 0) {
    return NextResponse.json({ ok: true, scanned: 0, alerts: 0 })
  }

  // Bulk-fetch existing watch state for the sessions in this batch so we
  // can compare against the previous evaluation without N queries.
  const ids = rows.map((r) => r.id)
  const { data: stateRows } = await supabase
    .from("terminal_watch_state")
    .select("session_id, last_evaluated_hash, last_alert_kind, last_alert_signature, last_alert_at, repeat_count")
    .in("session_id", ids)
    .returns<WatchStateRow[]>()
  const stateByid = new Map<string, WatchStateRow>()
  for (const s of stateRows ?? []) stateByid.set(s.session_id, s)

  let alerts = 0
  let suppressed = 0
  let skippedUnchanged = 0
  const now = Date.now()

  for (const row of rows) {
    const hash = snapshotHash(row.last_snapshot)
    const prev = stateByid.get(row.id)

    // No change since last pass — nothing to evaluate. We still want to
    // touch updated_at so the watcher's last-seen on this row stays
    // fresh; otherwise old rows would look stuck forever.
    if (hash && prev && prev.last_evaluated_hash === hash) {
      skippedUnchanged++
      await touch(supabase, row.id, row.user_id)
      continue
    }

    const cls = classify(row.last_snapshot, { lastSnapshotAt: row.last_snapshot_at, now })

    // No interesting state — record we saw the snapshot but don't alert.
    if (!cls) {
      await upsertState(supabase, {
        session_id: row.id,
        user_id: row.user_id,
        last_evaluated_hash: hash,
        last_evaluated_at: new Date(now).toISOString(),
        // Leave alert fields untouched — if a previous condition is gone,
        // we want the next occurrence to fire fresh, not be suppressed.
        last_alert_kind: prev?.last_alert_kind ?? null,
        last_alert_signature: prev?.last_alert_signature ?? null,
        last_alert_at: prev?.last_alert_at ?? null,
        repeat_count: 0,
      })
      continue
    }

    // Dedup: same kind + signature as last alert and we're still inside
    // the cooldown window? Bump repeat_count, skip the push.
    const sameAsLast =
      prev?.last_alert_kind === cls.kind &&
      prev?.last_alert_signature === cls.signature
    const withinCooldown =
      prev?.last_alert_at &&
      now - Date.parse(prev.last_alert_at) < ALERT_COOLDOWN_MS

    if (sameAsLast && withinCooldown) {
      suppressed++
      await upsertState(supabase, {
        session_id: row.id,
        user_id: row.user_id,
        last_evaluated_hash: hash,
        last_evaluated_at: new Date(now).toISOString(),
        last_alert_kind: prev!.last_alert_kind,
        last_alert_signature: prev!.last_alert_signature,
        last_alert_at: prev!.last_alert_at,
        repeat_count: (prev!.repeat_count ?? 0) + 1,
      })
      continue
    }

    // Fire. Build a user-facing title/body that reads at a glance — first
    // line is "what kind", second line is which session + a hint at why.
    const sessionLabel = row.title || lastPathSegment(row.folder) || "terminal"
    const title = pushTitleFor(cls.kind, sessionLabel)
    const body = trimForPush(`${cls.excerpt}`)
    const link = `nexus://terminals/${row.id}`

    let pushResult: { sent: number; skipped: number; failed: number } | null = null
    try {
      pushResult = await sendPushToAuthUser(row.user_id, "terminal.alert", {
        title,
        body,
        link,
        extra: {
          sessionId: row.id,
          alertKind: cls.kind,
          signature: cls.signature,
        },
      })
    } catch (err) {
      // Swallow — log row will record the absence below.
      pushResult = { sent: 0, skipped: 0, failed: 1 }
      console.error("[terminal-watcher] push failed:", err)
    }

    await supabase.from("terminal_watch_log").insert({
      session_id: row.id,
      user_id: row.user_id,
      alert_kind: cls.kind,
      signature: cls.signature,
      excerpt: cls.excerpt,
      push_result: pushResult,
    })

    await upsertState(supabase, {
      session_id: row.id,
      user_id: row.user_id,
      last_evaluated_hash: hash,
      last_evaluated_at: new Date(now).toISOString(),
      last_alert_kind: cls.kind,
      last_alert_signature: cls.signature,
      last_alert_at: new Date(now).toISOString(),
      repeat_count: 1,
    })
    alerts++
  }

  return NextResponse.json({
    ok: true,
    scanned: rows.length,
    alerts,
    suppressed,
    skippedUnchanged,
  })
}

// MARK: - helpers

async function upsertState(
  supabase: ReturnType<typeof createServiceClient>,
  row: {
    session_id: string
    user_id: string
    last_evaluated_hash: string | null
    last_evaluated_at: string
    last_alert_kind: string | null
    last_alert_signature: string | null
    last_alert_at: string | null
    repeat_count: number
  },
) {
  await supabase
    .from("terminal_watch_state")
    .upsert({ ...row, updated_at: new Date().toISOString() }, { onConflict: "session_id" })
}

async function touch(
  supabase: ReturnType<typeof createServiceClient>,
  sessionId: string,
  userId: string,
) {
  await supabase
    .from("terminal_watch_state")
    .upsert({
      session_id: sessionId,
      user_id: userId,
      updated_at: new Date().toISOString(),
    }, { onConflict: "session_id", ignoreDuplicates: false })
}

function pushTitleFor(kind: AlertKind, label: string): string {
  switch (kind) {
    case "blocker": return `Blocker in ${label}`
    case "confirm": return `${label} is waiting on you`
    case "done":    return `${label} finished`
    case "idle":    return `${label} went idle`
  }
}

function lastPathSegment(p: string): string {
  if (!p) return ""
  const parts = p.split("/").filter(Boolean)
  return parts[parts.length - 1] ?? p
}

// APNs payload cap is 4KB. The excerpt is already trimmed to ~240 chars
// in the classifier; this is a safety net for body assembly in case
// future code prefixes more context.
function trimForPush(s: string): string {
  if (s.length <= 240) return s
  return s.slice(0, 240) + "…"
}
