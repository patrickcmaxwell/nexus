// /api/push/devices
//
// POST   — register/update the calling human's device token.
//          Body: { platform, token, bundleId?, deviceLabel?, prefs? }
// GET    — list the calling human's devices.
// DELETE — body: { id } or { token } — revoke a single device.
//
// Auth: requires an active session. We use `humans.id` as the owner key
// because device-token push delivery is identity-scoped: the iPhone
// belongs to the human, not to a single auth.users row that might rotate.
import { NextRequest, NextResponse } from "next/server"
import { createClient } from "@supabase/supabase-js"
import { getActiveHuman } from "@/lib/auth/session"

function getServiceClient() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { persistSession: false, autoRefreshToken: false } }
  )
}

const VALID_PLATFORMS = new Set(["ios", "macos", "web", "android"])

interface Prefs {
  agentDone?: boolean
  scheduleFired?: boolean
  researchDone?: boolean
  opUpdated?: boolean
  terminalAlert?: boolean
}

export async function POST(req: NextRequest) {
  const me = await getActiveHuman()
  if (!me) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })

  const { platform, token, bundleId, deviceLabel, prefs } = await req.json().catch(() => ({}))
  if (typeof platform !== "string" || !VALID_PLATFORMS.has(platform)) {
    return NextResponse.json({ error: "platform must be ios|macos|web|android" }, { status: 400 })
  }
  if (typeof token !== "string" || token.trim().length < 8) {
    return NextResponse.json({ error: "token required" }, { status: 400 })
  }

  const p: Prefs = (prefs && typeof prefs === "object") ? prefs : {}
  const supabase = getServiceClient()

  // Upsert by (human_id, token). The same token re-registering shouldn't
  // duplicate rows or churn prefs — it should update last_seen_at and
  // refresh whatever fields the client sent.
  const update: Record<string, unknown> = {
    human_id: me.humanId,
    platform,
    token: token.trim(),
    bundle_id: typeof bundleId === "string" ? bundleId : null,
    device_label: typeof deviceLabel === "string" ? deviceLabel : null,
    last_seen_at: new Date().toISOString(),
    consecutive_failures: 0,
    last_error: null,
  }
  if (typeof p.agentDone === "boolean")      update.notify_agent_done      = p.agentDone
  if (typeof p.scheduleFired === "boolean")  update.notify_schedule_fired  = p.scheduleFired
  if (typeof p.researchDone === "boolean")   update.notify_research_done   = p.researchDone
  if (typeof p.opUpdated === "boolean")      update.notify_op_updated      = p.opUpdated
  if (typeof p.terminalAlert === "boolean")  update.notify_terminal_alert  = p.terminalAlert

  const { data, error } = await supabase
    .from("push_devices")
    .upsert(update, { onConflict: "human_id,token" })
    .select("id, platform, device_label, created_at, last_seen_at")
    .single()

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
  return NextResponse.json({ device: data })
}

export async function GET() {
  const me = await getActiveHuman()
  if (!me) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })

  const supabase = getServiceClient()
  const { data } = await supabase
    .from("push_devices")
    .select("id, platform, device_label, bundle_id, created_at, last_seen_at, last_sent_at, consecutive_failures, notify_agent_done, notify_schedule_fired, notify_research_done, notify_op_updated, notify_terminal_alert")
    .eq("human_id", me.humanId)
    .order("last_seen_at", { ascending: false })

  return NextResponse.json({ devices: data ?? [] })
}

export async function DELETE(req: NextRequest) {
  const me = await getActiveHuman()
  if (!me) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })

  const { id, token } = await req.json().catch(() => ({}))
  if (!id && !token) {
    return NextResponse.json({ error: "id or token required" }, { status: 400 })
  }

  const supabase = getServiceClient()
  let query = supabase.from("push_devices").delete().eq("human_id", me.humanId)
  if (id) query = query.eq("id", id)
  else if (token) query = query.eq("token", token)

  const { error } = await query
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ success: true })
}
