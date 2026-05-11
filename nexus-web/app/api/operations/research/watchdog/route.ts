export const maxDuration = 300

import { NextResponse } from "next/server"
import { after } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { getActiveAuthId } from "@/lib/auth/session"
import { runResearchJob } from "@/lib/operations/research-runner"

// Minutes before a "running" job is considered stuck.
const STUCK_MINUTES = 10
// Minutes before a "queued" job is considered abandoned.
const ABANDONED_MINUTES = 2

/**
 * Looks for research jobs that have been stuck too long and either resumes
 * them (if queued) or marks them failed so they don't hang forever.
 *
 * Eve or the user can poll this endpoint. The client dashboard hits it on
 * page load so research jobs survive preview cold-starts and deploys.
 */
export async function POST() {
  const authId = await getActiveAuthId()
  if (!authId) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const supabase = createServiceClient()

  const stuckCutoff = new Date(Date.now() - STUCK_MINUTES * 60_000).toISOString()
  const abandonedCutoff = new Date(Date.now() - ABANDONED_MINUTES * 60_000).toISOString()

  // Jobs that claim to be running but haven't updated in STUCK_MINUTES: fail them.
  const { data: stuck } = await supabase
    .from("research_jobs")
    .select("id")
    .eq("user_id", authId)
    .eq("status", "running")
    .lt("started_at", stuckCutoff)

  for (const s of stuck ?? []) {
    await supabase
      .from("research_jobs")
      .update({ status: "failed", error: "Timed out — runner never completed.", completed_at: new Date().toISOString() })
      .eq("id", s.id)
  }

  // Jobs that have been queued for too long: kick them off again.
  const { data: abandoned } = await supabase
    .from("research_jobs")
    .select("id")
    .eq("user_id", authId)
    .eq("status", "queued")
    .lt("created_at", abandonedCutoff)

  let resumed = 0
  for (const a of abandoned ?? []) {
    after(() => runResearchJob(a.id))
    resumed++
  }

  return NextResponse.json({
    stuckFailed: stuck?.length ?? 0,
    resumed,
  })
}
