// /api/schedules
//
// User-facing CRUD list/create endpoint for schedules. Scoped to the
// active human via getActiveAuthId(). All field validation lives here so
// the runner can trust DB rows blindly.

import { NextRequest, NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { getActiveAuthId } from "@/lib/auth/session"
import { validateCron, nextRunAt } from "@/lib/schedules/parser"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

const VALID_TARGETS = new Set(["eve_chat", "agent_run", "operation_brief", "arena_action"])

// GET /api/schedules — list this user's schedules, newest first
export async function GET() {
  const userId = await getActiveAuthId()
  if (!userId) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })

  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("schedules")
    .select("id, name, description, cron_expression, timezone, target_type, target_id, payload, enabled, next_run_at, last_run_at, last_status, last_error, created_at, updated_at")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ schedules: data ?? [] })
}

// POST /api/schedules — create a new schedule
//
// Body shape:
// {
//   name: string                                            (required)
//   description?: string
//   cron_expression: string                                 (required, validated)
//   timezone?: string                                       (default: America/Chicago)
//   target_type: 'eve_chat'|'agent_run'|'operation_brief'|'arena_action'   (required)
//   target_id?: string                                      (uuid; required for non-arena_action)
//   payload?: Record<string, unknown>                       (target-specific)
//   enabled?: boolean                                       (default true)
// }
export async function POST(req: NextRequest) {
  const userId = await getActiveAuthId()
  if (!userId) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })

  const body = await req.json().catch(() => ({}))
  const {
    name,
    description,
    cron_expression,
    timezone = "America/Chicago",
    target_type,
    target_id = null,
    payload = {},
    enabled = true,
  } = body as {
    name?: string
    description?: string
    cron_expression?: string
    timezone?: string
    target_type?: string
    target_id?: string | null
    payload?: Record<string, unknown>
    enabled?: boolean
  }

  if (!name || typeof name !== "string" || !name.trim()) {
    return NextResponse.json({ error: "name required" }, { status: 400 })
  }
  if (!target_type || !VALID_TARGETS.has(target_type)) {
    return NextResponse.json({ error: `target_type must be one of: ${[...VALID_TARGETS].join(", ")}` }, { status: 400 })
  }
  if (target_type !== "arena_action" && !target_id) {
    return NextResponse.json({ error: `${target_type} requires target_id` }, { status: 400 })
  }
  const valid = validateCron(cron_expression ?? "", timezone)
  if (!valid.ok) {
    return NextResponse.json({ error: `invalid cron: ${valid.reason}` }, { status: 400 })
  }

  let initialNext: string
  try {
    initialNext = nextRunAt(cron_expression!, timezone).toISOString()
  } catch (err) {
    const msg = err instanceof Error ? err.message : "next_run_at compute failed"
    return NextResponse.json({ error: msg }, { status: 400 })
  }

  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("schedules")
    .insert({
      user_id: userId,
      name: name.trim().slice(0, 200),
      description: description ? String(description).slice(0, 1000) : null,
      cron_expression: cron_expression!.trim(),
      timezone,
      target_type,
      target_id,
      payload,
      enabled,
      next_run_at: initialNext,
    })
    .select()
    .single()

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ schedule: data }, { status: 201 })
}
