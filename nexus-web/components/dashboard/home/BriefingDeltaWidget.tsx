"use client"

// "What changed since last visit" stripe — mirrors Lumen's deltaSection.
// Fetches /api/eve/briefing on mount, persists last-seen timestamp in
// localStorage so each visit shows only what's new since the previous one.

import { useEffect, useState } from "react"
import {
  PlusCircle, RefreshCw, FileText, Target, CheckCircle2,
} from "lucide-react"

type BriefingOp = { id: string; label: string; status: string; priority: string }
type BriefingRecord = { id: string; title: string; type: string; operationLabel: string }
type BriefingResearch = { id: string; operationLabel: string; summary: string }

type Briefing = {
  since: string
  now: string
  stats: {
    activeOps: number
    activeAgents: number
    activeDirectives: number
    memories: number
  }
  delta: {
    newOperations: BriefingOp[]
    statusChangedOperations: BriefingOp[]
    newRecords: BriefingRecord[]
    findings: {
      totalCount: number
      perAgent: Record<string, number>
      latest: Array<{ agent: string; summary: string; createdAt: string }>
    }
    completedResearch: BriefingResearch[]
  }
}

const STORAGE_KEY = "nexus.lastBriefingFetchedAt"

export default function BriefingDeltaWidget() {
  const [briefing, setBriefing] = useState<Briefing | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    const lastSince = typeof window !== "undefined" ? localStorage.getItem(STORAGE_KEY) : null
    const url = lastSince
      ? `/api/eve/briefing?since=${encodeURIComponent(lastSince)}`
      : "/api/eve/briefing"

    fetch(url, { cache: "no-store" })
      .then(async (r) => {
        if (!r.ok) throw new Error(`HTTP ${r.status}`)
        return r.json() as Promise<Briefing>
      })
      .then((b) => {
        setBriefing(b)
        if (typeof window !== "undefined") localStorage.setItem(STORAGE_KEY, b.now)
      })
      .catch((e) => setError(e instanceof Error ? e.message : String(e)))
      .finally(() => setLoading(false))
  }, [])

  if (loading) return null
  if (error) return null
  if (!briefing) return null

  const d = briefing.delta
  const hasAnything =
    d.newOperations.length > 0 ||
    d.statusChangedOperations.length > 0 ||
    d.newRecords.length > 0 ||
    d.findings.totalCount > 0 ||
    d.completedResearch.length > 0

  if (!hasAnything) return null

  return (
    <section className="rounded-xl border border-border bg-card p-5 flex flex-col gap-3">
      <header className="flex items-center gap-2">
        <h2 className="text-[9px] font-mono font-bold tracking-[0.18em] text-muted-foreground uppercase">
          What changed since last visit
        </h2>
        <div className="flex-1 h-px bg-border" />
      </header>

      {/* Counter pills */}
      <div className="flex flex-wrap gap-2">
        {d.newOperations.length > 0 && (
          <Pill label="NEW OPS" value={d.newOperations.length} color="violet" />
        )}
        {d.statusChangedOperations.length > 0 && (
          <Pill label="STATUS Δ" value={d.statusChangedOperations.length} color="amber" />
        )}
        {d.newRecords.length > 0 && (
          <Pill label="NEW RECORDS" value={d.newRecords.length} color="cyan" />
        )}
        {d.findings.totalCount > 0 && (
          <Pill label="FINDINGS" value={d.findings.totalCount} color="rose" />
        )}
        {d.completedResearch.length > 0 && (
          <Pill label="RESEARCH ✓" value={d.completedResearch.length} color="violet" />
        )}
      </div>

      {/* Inline rows: top items per type */}
      <div className="flex flex-col gap-1.5">
        {d.newOperations.slice(0, 3).map((op) => (
          <Row
            key={op.id}
            Icon={PlusCircle}
            color="text-violet-400"
            primary={op.label}
            secondary={`operation · ${op.status.toUpperCase()}`}
          />
        ))}
        {d.statusChangedOperations.slice(0, 3).map((op) => (
          <Row
            key={op.id}
            Icon={RefreshCw}
            color="text-amber-400"
            primary={op.label}
            secondary={`moved to ${op.status.toUpperCase()}`}
          />
        ))}
        {d.newRecords.slice(0, 4).map((r) => (
          <Row
            key={r.id}
            Icon={FileText}
            color="text-primary"
            primary={r.title}
            secondary={`${r.type.toUpperCase()} · ${r.operationLabel}`}
          />
        ))}
        {Object.entries(d.findings.perAgent).slice(0, 4).map(([agent, count]) => (
          <Row
            key={agent}
            Icon={Target}
            color="text-rose-400"
            primary={`${agent} surfaced ${count} finding${count === 1 ? "" : "s"}`}
            secondary=""
          />
        ))}
        {d.completedResearch.slice(0, 2).map((r) => (
          <Row
            key={r.id}
            Icon={CheckCircle2}
            color="text-violet-400"
            primary={`Research complete${r.operationLabel ? ` · ${r.operationLabel}` : ""}`}
            secondary={r.summary}
          />
        ))}
      </div>
    </section>
  )
}

function Pill({ label, value, color }: { label: string; value: number; color: "violet" | "amber" | "cyan" | "rose" }) {
  const cls: Record<typeof color, string> = {
    violet: "text-violet-400 border-violet-400/35 bg-violet-400/10",
    amber:  "text-amber-400 border-amber-400/35 bg-amber-400/10",
    cyan:   "text-primary border-primary/35 bg-primary/10",
    rose:   "text-rose-400 border-rose-400/35 bg-rose-400/10",
  }
  return (
    <span className={`inline-flex items-center gap-1.5 px-2 py-1 rounded-full border ${cls[color]}`}>
      <span className="font-mono font-bold text-[12px]">{value}</span>
      <span className="font-mono font-bold text-[8px] tracking-[0.15em] text-muted-foreground">
        {label}
      </span>
    </span>
  )
}

function Row({
  Icon, color, primary, secondary,
}: {
  Icon: React.ComponentType<{ size?: number; className?: string }>
  color: string
  primary: string
  secondary: string
}) {
  return (
    <div className="flex items-start gap-2.5 px-2 py-1 rounded bg-muted/30">
      <Icon size={12} className={`mt-0.5 flex-shrink-0 ${color}`} />
      <div className="min-w-0 flex-1">
        <p className="text-[12px] font-medium text-card-foreground leading-snug truncate">{primary}</p>
        {secondary && (
          <p className="text-[10px] text-muted-foreground leading-snug line-clamp-1">{secondary}</p>
        )}
      </div>
    </div>
  )
}
