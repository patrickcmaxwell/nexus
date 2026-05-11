// /dashboard/agents/[id] — per-agent detail route. Full view of an agent:
// identity, capabilities, directives, recent run telemetry. Replaces the
// in-page detail panel for deep-linking and full-screen review.

import Link from "next/link"
import { notFound, redirect } from "next/navigation"
import { ChevronLeft } from "lucide-react"
import { getActiveAuthId } from "@/lib/auth/session"
import { createServiceClient } from "@/lib/supabase/service"
import AgentDetailClient from "./AgentDetailClient"

export const dynamic = "force-dynamic"

export default async function AgentDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const userId = await getActiveAuthId()
  if (!userId) redirect("/auth/login")
  const { id } = await params

  const supabase = createServiceClient()

  const { data: agent } = await supabase
    .from("agents")
    .select("id, name, role, personality, capabilities, directives, status, created_at, last_scanned_at, total_findings")
    .eq("id", id)
    .eq("user_id", userId)
    .maybeSingle()

  if (!agent) notFound()

  // Recent findings produced by this agent.
  const { data: recentFindings } = await supabase
    .from("agent_findings")
    .select("id, title, description, type, priority, created_at")
    .eq("agent_id", id)
    .order("created_at", { ascending: false })
    .limit(20)

  return (
    <main className="min-h-screen px-4 sm:px-6 md:px-10 py-8 max-w-5xl mx-auto">
      <Link
        href="/dashboard/agents"
        className="inline-flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground mb-6"
      >
        <ChevronLeft size={14} /> All agents
      </Link>

      <AgentDetailClient
        agent={agent as never}
        recentFindings={(recentFindings ?? []) as never}
      />
    </main>
  )
}
