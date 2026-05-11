// /api/schedules/runner
//
// Vercel Cron entry. Configured in vercel.json to fire every minute.
// On each tick:
//   1. Verify the Vercel-Cron Authorization header.
//   2. SELECT all enabled schedules where next_run_at <= now() (LIMIT 50).
//   3. For each: optimistic-lock by setting a new next_run_at FIRST (so a
//      slow-running runner in the previous tick can't double-fire), then
//      dispatch the target action.
//   4. Insert a schedule_runs row with the result + duration.
//   5. Update last_run_at / last_status / last_error on the schedule.
//
// Best-effort: a single failing schedule never blocks the rest. Errors are
// captured per-schedule and surfaced in the audit log.

import { NextRequest, NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { nextRunAt } from "@/lib/schedules/parser"
import { dispatch } from "@/lib/schedules/dispatchers"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"
export const maxDuration = 60

const RUNNER_BUDGET_MS = 50_000  // leave headroom under maxDuration for shutdown

type ScheduleRow = {
  id: string
  user_id: string
  name: string
  cron_expression: string
  timezone: string
  target_type: "eve_chat" | "agent_run" | "operation_brief" | "arena_action"
  target_id: string | null
  payload: Record<string, unknown> | null
  next_run_at: string
}

export async function GET(req: NextRequest) {
  return run(req)
}

export async function POST(req: NextRequest) {
  return run(req)
}

async function run(req: NextRequest): Promise<NextResponse> {
  // Vercel Cron sends "Authorization: Bearer ${CRON_SECRET}" automatically
  // when the cron is registered in vercel.json and the env var is set.
  // Manual probes can use the same header.
  const expected = process.env.CRON_SECRET
  if (!expected) {
    return NextResponse.json({ error: "CRON_SECRET not configured" }, { status: 500 })
  }
  const authz = req.headers.get("authorization")
  if (authz !== `Bearer ${expected}`) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }

  const supabase = createServiceClient()
  const tickStart = Date.now()

  const { data: due, error: selectError } = await supabase
    .from("schedules")
    .select("id, user_id, name, cron_expression, timezone, target_type, target_id, payload, next_run_at")
    .eq("enabled", true)
    .lte("next_run_at", new Date().toISOString())
    .limit(50)

  if (selectError) {
    console.error("[schedules] select failed:", selectError.message)
    return NextResponse.json({ error: "select_failed", detail: selectError.message }, { status: 500 })
  }

  const rows = (due ?? []) as ScheduleRow[]
  let fired = 0
  let errors = 0
  const results: Array<{ id: string; status: string; error?: string }> = []

  for (const row of rows) {
    if (Date.now() - tickStart > RUNNER_BUDGET_MS) {
      console.warn("[schedules] runner budget exceeded, deferring remaining")
      break
    }
    const r = await processOne(supabase, row)
    if (r.status === "success") fired++
    else errors++
    results.push({ id: row.id, status: r.status, error: r.status === "error" ? r.error : undefined })
  }

  return NextResponse.json({
    scanned: rows.length,
    fired,
    errors,
    durationMs: Date.now() - tickStart,
    results,
  })
}

async function processOne(
  supabase: ReturnType<typeof createServiceClient>,
  row: ScheduleRow,
): Promise<{ status: "success" | "error"; error?: string }> {
  // Compute the next firing BEFORE we run the work, then optimistic-lock
  // by including the previous next_run_at in the UPDATE WHERE clause.
  // If a parallel runner already moved the row forward, our update touches
  // 0 rows and we abort — preventing double-fire.
  const previousNextRun = row.next_run_at
  let computedNext: string
  try {
    computedNext = nextRunAt(row.cron_expression, row.timezone || "America/Chicago").toISOString()
  } catch (err) {
    const msg = err instanceof Error ? err.message : "cron parse failed"
    await recordRun(supabase, row.id, "error", null, `cron parse failed: ${msg}`, 0)
    await supabase
      .from("schedules")
      .update({
        last_run_at: new Date().toISOString(),
        last_status: "error",
        last_error: msg,
        enabled: false,  // disable a schedule we can't even parse — user must fix
        updated_at: new Date().toISOString(),
      })
      .eq("id", row.id)
    return { status: "error", error: msg }
  }

  const { data: locked, error: lockError } = await supabase
    .from("schedules")
    .update({ next_run_at: computedNext })
    .eq("id", row.id)
    .eq("next_run_at", previousNextRun)
    .select("id")

  if (lockError) {
    return { status: "error", error: `lock failed: ${lockError.message}` }
  }
  if (!locked || locked.length === 0) {
    // Already taken by a concurrent runner — silently skip.
    return { status: "success" }
  }

  // Lock acquired. Run the dispatcher.
  const startedAt = Date.now()
  let dispatchResult
  try {
    dispatchResult = await dispatch({
      scheduleId:   row.id,
      scheduleName: row.name,
      userId:       row.user_id,
      targetType:   row.target_type,
      targetId:     row.target_id,
      payload:      row.payload ?? {},
    })
  } catch (err) {
    dispatchResult = { status: "error" as const, error: err instanceof Error ? err.message : "dispatcher threw" }
  }
  const durationMs = Date.now() - startedAt

  // Audit + update last_* fields. Both are best-effort; failure is logged
  // but does not propagate.
  if (dispatchResult.status === "success") {
    await recordRun(supabase, row.id, "success", dispatchResult.result, null, durationMs)
    await supabase
      .from("schedules")
      .update({
        last_run_at: new Date().toISOString(),
        last_status: "success",
        last_error: null,
        updated_at: new Date().toISOString(),
      })
      .eq("id", row.id)
    return { status: "success" }
  } else {
    await recordRun(supabase, row.id, "error", null, dispatchResult.error, durationMs)
    await supabase
      .from("schedules")
      .update({
        last_run_at: new Date().toISOString(),
        last_status: "error",
        last_error: dispatchResult.error.slice(0, 500),
        updated_at: new Date().toISOString(),
      })
      .eq("id", row.id)
    return { status: "error", error: dispatchResult.error }
  }
}

async function recordRun(
  supabase: ReturnType<typeof createServiceClient>,
  scheduleId: string,
  status: "success" | "error" | "skipped",
  result: Record<string, unknown> | null,
  errorMsg: string | null,
  durationMs: number,
): Promise<void> {
  try {
    await supabase
      .from("schedule_runs")
      .insert({
        schedule_id: scheduleId,
        fired_at: new Date().toISOString(),
        status,
        result,
        error_msg: errorMsg,
        duration_ms: durationMs,
      })
  } catch (err) {
    console.error("[schedules] failed to record run:", err)
  }
}
