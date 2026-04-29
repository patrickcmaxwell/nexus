export const maxDuration = 300 // background work can run up to 5 min

import { NextRequest, NextResponse } from "next/server"
import { after } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { isAuthed, USER_ID } from "@/lib/operations/auth"
import { runResearchJob } from "@/lib/operations/research-runner"

// GET — list research jobs for this record (most recent first)
export async function GET(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  if (!(await isAuthed())) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const { id } = await params
  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("research_jobs")
    .select("*")
    .eq("record_id", id)
    .eq("user_id", USER_ID)
    .order("created_at", { ascending: false })
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json(data ?? [])
}

// POST — kick off a new research job. Returns immediately; Eve works in the
// background via Next.js `after()`.
export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  if (!(await isAuthed())) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const { id } = await params
  const { prompt, model } = await req.json().catch(() => ({}))

  const supabase = createServiceClient()

  // Verify the parent record exists and belongs to this user
  const { data: parent } = await supabase
    .from("operation_records")
    .select("id, operation_id")
    .eq("id", id)
    .eq("user_id", USER_ID)
    .single()

  if (!parent) return NextResponse.json({ error: "Record not found" }, { status: 404 })

  // Guard: refuse to queue a second job while one is already running for
  // this record. Eve should not stampede herself.
  const { data: running } = await supabase
    .from("research_jobs")
    .select("id")
    .eq("record_id", id)
    .eq("user_id", USER_ID)
    .in("status", ["queued", "running"])
    .limit(1)

  if (running && running.length > 0) {
    return NextResponse.json({ error: "A research job is already running for this record.", jobId: running[0].id }, { status: 409 })
  }

  const { data: job, error } = await supabase
    .from("research_jobs")
    .insert({
      record_id: id,
      operation_id: parent.operation_id,
      user_id: USER_ID,
      status: "queued",
      prompt: prompt ?? null,
      model: model ?? "grok-4-fast-reasoning",
      assigned_to: "eve",
    })
    .select()
    .single()

  if (error || !job) return NextResponse.json({ error: error?.message ?? "Failed to queue" }, { status: 500 })

  // Fire-and-forget the runner. Next.js keeps the function alive for the
  // duration of `maxDuration` so the research completes server-side.
  after(() => runResearchJob(job.id))

  return NextResponse.json(job)
}
