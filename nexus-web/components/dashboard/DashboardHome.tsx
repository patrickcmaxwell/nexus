"use client"

import { useCallback, useEffect, useRef, useState } from "react"
import EveCommand from "./home/EveCommand"
import ActiveResearchWidget from "./home/ActiveResearchWidget"
import PinnedRecordsWidget from "./home/PinnedRecordsWidget"
import ActionItemsWidget from "./home/ActionItemsWidget"
import ActivityFeedWidget from "./home/ActivityFeedWidget"

export type Overview = {
  greeting: string
  suggestions: string[]
  stats: {
    conversations: number
    memories: number
    operations: number
    agents: number
    records: number
    activeOperations: number
    activeResearch: number
  }
  operations: Array<{ id: string; name: string; status: string; priority: string; codename: string | null; updated_at: string }>
  agents: Array<{ id: string; name: string; status: string }>
  activeResearch: Array<{
    id: string
    operation_id: string
    record_id: string | null
    operation_name: string
    record_title: string | null
    model: string | null
    status: string
    prompt: string
    progress_note: string | null
    findings_count: number | null
    started_at: string | null
    created_at: string
  }>
  pinnedRecords: Array<{
    id: string
    operation_id: string
    operation_name: string
    title: string
    type: string
    status: string | null
    priority: string
    pinned: boolean
    updated_at: string
  }>
  actionItems: Array<{
    id: string
    brief_id: string
    operation_id: string
    operation_name: string
    kind: "actions" | "next_steps"
    text: string
    generated_at: string
  }>
  activity: Array<{
    id: string
    kind: "record_created" | "research_completed" | "research_started" | "brief_generated" | "conversation"
    title: string
    subtitle: string
    at: string
    href: string
    accent: string
  }>
  lastConversation: {
    id: string
    title: string
    messages: Array<{ role: string; content: string; created_at: string }>
  } | null
}

export default function DashboardHome({ initial }: { initial: Overview }) {
  const [data, setData] = useState<Overview>(initial)
  const [loading, setLoading] = useState(false)

  const fetchOverview = useCallback(async (opts?: { silent?: boolean }) => {
    if (!opts?.silent) setLoading(true)
    try {
      const res = await fetch("/api/dashboard/overview", { cache: "no-store" })
      if (res.ok) {
        const next = await res.json()
        setData(next)
      }
    } finally {
      if (!opts?.silent) setLoading(false)
    }
  }, [])

  // Smart polling: 10s when research is running, 30s otherwise. Pause on
  // tab hide. Matches the Nexus Map cadence so they feel unified.
  const activeResearch = data.stats.activeResearch
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null)
  useEffect(() => {
    const interval = activeResearch > 0 ? 10_000 : 30_000
    const start = () => {
      if (timerRef.current) return
      timerRef.current = setInterval(() => fetchOverview({ silent: true }), interval)
    }
    const stop = () => { if (timerRef.current) { clearInterval(timerRef.current); timerRef.current = null } }
    const onVis = () => (document.visibilityState === "visible" ? start() : stop())
    document.addEventListener("visibilitychange", onVis)
    if (document.visibilityState === "visible") start()
    return () => { stop(); document.removeEventListener("visibilitychange", onVis) }
  }, [activeResearch, fetchOverview])

  return (
    // On desktop: constrain to viewport height and let each column scroll independently.
    // On mobile: let the page flow naturally and stack vertically.
    <div className="flex flex-col lg:flex-row lg:h-screen lg:overflow-hidden">
      {/* Left: Eve command center — particle face + input + voice */}
      <aside className="lg:w-[46%] xl:w-[42%] lg:border-r border-border flex-none lg:h-full lg:overflow-y-auto">
        <EveCommand
          greeting={data.greeting}
          suggestions={data.suggestions}
          lastConversation={data.lastConversation}
          activeResearch={data.stats.activeResearch}
          onActivity={() => fetchOverview({ silent: true })}
        />
      </aside>

      {/* Right: live system data */}
      <section className="flex-1 min-w-0 lg:h-full lg:overflow-y-auto">
        <div className="p-5 lg:p-6 space-y-4 max-w-3xl">
          {/* Header stats strip */}
          <header className="flex items-center justify-between gap-4 flex-wrap">
            <div>
              <h1 className="text-lg font-semibold text-foreground tracking-tight">Command Deck</h1>
              <p className="text-xs text-muted-foreground font-mono mt-0.5">
                {data.stats.activeOperations} active ops · {data.stats.records} records · {data.stats.memories} memories
              </p>
            </div>
            <button
              onClick={() => fetchOverview()}
              disabled={loading}
              className="text-[10px] font-mono uppercase tracking-widest px-3 py-1.5 rounded border border-border hover:border-accent/40 hover:text-accent transition-colors text-muted-foreground disabled:opacity-50"
            >
              {loading ? "Refreshing…" : "Refresh"}
            </button>
          </header>

          <ActiveResearchWidget jobs={data.activeResearch} />
          <PinnedRecordsWidget records={data.pinnedRecords} />
          <ActionItemsWidget items={data.actionItems} />
          <ActivityFeedWidget activity={data.activity} />
        </div>
      </section>
    </div>
  )
}
