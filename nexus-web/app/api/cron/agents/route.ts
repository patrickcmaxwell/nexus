import { NextRequest, NextResponse } from "next/server"
import { Client as QStashClient } from "@upstash/qstash"
import { createServiceClient } from "@/lib/supabase/service"

/**
 * GET /api/cron/agents
 * Called by Vercel Cron on schedule. Finds all ACTIVE agents across every
 * user and triggers a QStash-backed scan for each one. Falls back to a
 * direct in-process scan if QStash keys are not configured (local dev).
 *
 * Multi-user note: this iterates every active agent regardless of owner —
 * each agent's `user_id` is preserved on its row, and /api/agents/process
 * scopes its queries by that field, so Londynn's agents get scanned with
 * her data and Patrick's get scanned with his.
 */
export async function GET(req: NextRequest) {
  // Vercel cron sends this header; require it in production
  const authHeader = req.headers.get("authorization")
  if (process.env.NODE_ENV === "production" && authHeader !== `Bearer ${process.env.CRON_SECRET}`) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }

  const supabase = createServiceClient()

  const { data: agents, error } = await supabase
    .from("agents")
    .select("id, name, status, last_scanned_at, scan_interval_hours, user_id")
    .eq("status", "active")

  if (error) {
    console.error("[cron/agents] Failed to fetch agents:", error)
    return NextResponse.json({ error: error.message }, { status: 500 })
  }

  if (!agents?.length) {
    return NextResponse.json({ triggered: 0, message: "No active agents" })
  }

  const now = new Date()
  const toTrigger = agents.filter((agent) => {
    if (!agent.last_scanned_at) return true
    const intervalHours = agent.scan_interval_hours ?? 12
    const lastScan = new Date(agent.last_scanned_at)
    const hoursSince = (now.getTime() - lastScan.getTime()) / 1000 / 3600
    return hoursSince >= intervalHours
  })

  if (!toTrigger.length) {
    return NextResponse.json({ triggered: 0, message: "All agents scanned recently" })
  }

  const appUrl = process.env.NEXT_PUBLIC_APP_URL ?? "http://localhost:3000"

  if (process.env.QSTASH_TOKEN) {
    // Prod: fan out via QStash so each scan runs independently
    const qstash = new QStashClient({ token: process.env.QSTASH_TOKEN })
    const results = await Promise.allSettled(
      toTrigger.map((agent) =>
        qstash.publishJSON({
          url: `${appUrl}/api/agents/process`,
          body: { agentId: agent.id, cursor: 0, isFirstRun: true, totalFindings: 0, conversationsScanned: 0 },
          retries: 2,
        })
      )
    )
    const succeeded = results.filter((r) => r.status === "fulfilled").length
    console.log(`[cron/agents] Triggered ${succeeded}/${toTrigger.length} agents via QStash`)
    return NextResponse.json({ triggered: succeeded, total: toTrigger.length })
  } else {
    // Dev fallback: trigger directly via internal fetch (synchronous, no timeout bypass)
    const results = await Promise.allSettled(
      toTrigger.map((agent) =>
        fetch(`${appUrl}/api/agents/run`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ agentId: agent.id }),
        })
      )
    )
    const succeeded = results.filter((r) => r.status === "fulfilled").length
    return NextResponse.json({ triggered: succeeded, total: toTrigger.length, mode: "direct" })
  }
}
