// /api/schedules/[id]/run
//
// Manually fire a schedule right now — same dispatcher path the cron
// runner uses, just triggered by a user button instead of a tick. Useful
// for verifying a new schedule without waiting up to a minute, and for
// "re-run last failure" semantics from the audit log row.
//
// Does NOT advance next_run_at — the next cron tick still fires at the
// scheduled time. This is a side-channel run, not a replacement for the
// regular firing.

import { NextRequest, NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { getActiveAuthId } from "@/lib/auth/session"
import { dispatch } from "@/lib/schedules/dispatchers"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"
export const maxDuration = 60

export async function POST(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const userId = await getActiveAuthId()
  if (!userId) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
  const { id } = await params
  const supabase = createServiceClient()

  const { data: row } = await supabase
    .from("schedules")
    .select("id, user_id, name, target_type, target_id, payload")
    .eq("id", id)
    .eq("user_id", userId)
    .maybeSingle()
  if (!row) return NextResponse.json({ error: "Not found" }, { status: 404 })

  const startedAt = Date.now()
  let result
  try {
    result = await dispatch({
      scheduleId:   row.id,
      scheduleName: row.name,
      userId:       row.user_id,
      targetType:   row.target_type,
      targetId:     row.target_id,
      payload:      (row.payload as Record<string, unknown> | null) ?? {},
    })
  } catch (err) {
    result = { status: "error" as const, error: err instanceof Error ? err.message : "dispatcher threw" }
  }
  const durationMs = Date.now() - startedAt

  // Audit-log this manual firing too — distinguish via result.manual flag.
  await supabase
    .from("schedule_runs")
    .insert({
      schedule_id: id,
      fired_at: new Date().toISOString(),
      status: result.status,
      result: result.status === "success" ? { ...result.result, manual: true } : null,
      error_msg: result.status === "error" ? result.error : null,
      duration_ms: durationMs,
    })

  // Bump last_* on the schedule so the UI reflects this run too.
  await supabase
    .from("schedules")
    .update({
      last_run_at: new Date().toISOString(),
      last_status: result.status,
      last_error:  result.status === "error" ? result.error.slice(0, 500) : null,
      updated_at:  new Date().toISOString(),
    })
    .eq("id", id)

  return NextResponse.json({
    success: result.status === "success",
    status:  result.status,
    durationMs,
    ...(result.status === "success" ? { result: result.result } : { error: result.error }),
  })
}
