// /api/schedules/[id]
//
// Per-schedule GET / PATCH / DELETE. Always scoped to the active user
// via getActiveAuthId() — no cross-user reads or mutations.

import { NextRequest, NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { getActiveAuthId } from "@/lib/auth/session"
import { validateCron, nextRunAt } from "@/lib/schedules/parser"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

export async function GET(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const userId = await getActiveAuthId()
  if (!userId) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
  const { id } = await params
  const supabase = createServiceClient()

  const { data: schedule } = await supabase
    .from("schedules")
    .select("*")
    .eq("id", id)
    .eq("user_id", userId)
    .maybeSingle()
  if (!schedule) return NextResponse.json({ error: "Not found" }, { status: 404 })

  const { data: runs } = await supabase
    .from("schedule_runs")
    .select("id, fired_at, status, result, error_msg, duration_ms")
    .eq("schedule_id", id)
    .order("fired_at", { ascending: false })
    .limit(20)

  return NextResponse.json({ schedule, runs: runs ?? [] })
}

export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const userId = await getActiveAuthId()
  if (!userId) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
  const { id } = await params
  const body = await req.json().catch(() => ({}))
  const supabase = createServiceClient()

  const { data: existing } = await supabase
    .from("schedules")
    .select("id, cron_expression, timezone")
    .eq("id", id)
    .eq("user_id", userId)
    .maybeSingle()
  if (!existing) return NextResponse.json({ error: "Not found" }, { status: 404 })

  const update: Record<string, unknown> = { updated_at: new Date().toISOString() }

  if (typeof body.name === "string")        update.name = body.name.trim().slice(0, 200)
  if (typeof body.description === "string") update.description = body.description.slice(0, 1000)
  if (typeof body.enabled === "boolean")    update.enabled = body.enabled
  if (body.payload && typeof body.payload === "object") update.payload = body.payload

  // Cron / timezone changes recompute next_run_at.
  const newCron = typeof body.cron_expression === "string" ? body.cron_expression.trim() : null
  const newTz   = typeof body.timezone === "string" ? body.timezone : null
  if (newCron !== null || newTz !== null) {
    const expr = newCron ?? existing.cron_expression
    const tz   = newTz   ?? existing.timezone ?? "America/Chicago"
    const valid = validateCron(expr, tz)
    if (!valid.ok) return NextResponse.json({ error: `invalid cron: ${valid.reason}` }, { status: 400 })
    if (newCron !== null) update.cron_expression = expr
    if (newTz   !== null) update.timezone = tz
    try {
      update.next_run_at = nextRunAt(expr, tz).toISOString()
    } catch (err) {
      return NextResponse.json({ error: err instanceof Error ? err.message : "next_run_at compute failed" }, { status: 400 })
    }
  }

  // Re-enabling a schedule should also bump next_run_at to "next valid
  // time from now" so it doesn't immediately fire on a stale next_run_at.
  if (body.enabled === true) {
    try {
      const expr = newCron ?? existing.cron_expression
      const tz   = newTz   ?? existing.timezone ?? "America/Chicago"
      update.next_run_at = nextRunAt(expr, tz).toISOString()
    } catch { /* keep existing */ }
  }

  const { data, error } = await supabase
    .from("schedules")
    .update(update)
    .eq("id", id)
    .eq("user_id", userId)
    .select()
    .single()

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ schedule: data })
}

export async function DELETE(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const userId = await getActiveAuthId()
  if (!userId) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
  const { id } = await params
  const supabase = createServiceClient()

  const { error } = await supabase
    .from("schedules")
    .delete()
    .eq("id", id)
    .eq("user_id", userId)

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ success: true })
}
