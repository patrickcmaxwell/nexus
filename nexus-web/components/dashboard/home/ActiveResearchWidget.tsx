"use client"

import Link from "next/link"
import { Telescope, ArrowRight } from "lucide-react"

type Job = {
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
}

function timeAgo(iso: string | null) {
  if (!iso) return ""
  const s = Math.floor((Date.now() - new Date(iso).getTime()) / 1000)
  if (s < 60) return `${s}s ago`
  if (s < 3600) return `${Math.floor(s / 60)}m ago`
  return `${Math.floor(s / 3600)}h ago`
}

export default function ActiveResearchWidget({ jobs }: { jobs: Job[] }) {
  if (!jobs.length) return null

  return (
    <section className="rounded-xl border border-border bg-card overflow-hidden">
      <header className="flex items-center justify-between px-4 py-3 border-b border-primary/10">
        <div className="flex items-center gap-2">
          <div className="w-7 h-7 rounded-lg flex items-center justify-center bg-primary/10 border border-primary/20">
            <Telescope size={13} className="text-primary" />
          </div>
          <div>
            <h2 className="text-[13px] font-semibold text-foreground">Active Research</h2>
            <p className="text-[10px] text-muted-foreground font-mono">{jobs.length} {jobs.length === 1 ? "job" : "jobs"} running</p>
          </div>
        </div>
      </header>

      <div className="divide-y divide-border">
        {jobs.map(j => {
          const isRunning = j.status === "running"
          const isQueued = j.status === "queued"
          return (
            <Link
              key={j.id}
              href={j.record_id ? `/dashboard/operations?record=${j.record_id}` : "/dashboard/operations"}
              className="flex items-center gap-3 px-4 py-3 hover:bg-primary/[0.04] transition-colors group"
            >
              <ProgressRing running={isRunning} queued={isQueued} />
              <div className="flex-1 min-w-0">
                <div className="flex items-baseline gap-2">
                  <span className="text-[13px] font-medium truncate text-foreground">
                    {j.record_title ?? j.prompt.slice(0, 60)}
                  </span>
                  <span className="text-xs font-medium text-primary/70">
                    {j.status}
                  </span>
                </div>
                <p className="text-[11px] text-muted-foreground truncate mt-0.5">
                  {j.progress_note ?? j.prompt.slice(0, 80)}
                </p>
                <p className="text-[9px] font-mono text-muted-foreground/60 mt-0.5">
                  {j.operation_name}
                  {j.model ? ` · ${j.model}` : ""}
                  {j.started_at ? ` · started ${timeAgo(j.started_at)}` : j.created_at ? ` · queued ${timeAgo(j.created_at)}` : ""}
                </p>
              </div>
              <ArrowRight size={12} className="text-muted-foreground/40 group-hover:text-primary transition-colors flex-none" />
            </Link>
          )
        })}
      </div>
    </section>
  )
}

function ProgressRing({ running, queued }: { running: boolean; queued: boolean }) {
  // Animated SVG progress ring. Running = sweeping arc, queued = dashed, else = static.
  return (
    <div className="relative w-8 h-8 flex-none">
      <svg viewBox="0 0 32 32" className="w-full h-full">
        {/* Track */}
        <circle cx="16" cy="16" r="13" fill="none" stroke="rgba(6,182,212,0.15)" strokeWidth="2" />
        {/* Sweep */}
        {running && (
          <circle
            cx="16" cy="16" r="13" fill="none"
            stroke="#06b6d4" strokeWidth="2.5" strokeLinecap="round"
            strokeDasharray="30 82" transform="rotate(-90 16 16)"
            className="animate-[spin_1.4s_linear_infinite]"
          />
        )}
        {queued && (
          <circle
            cx="16" cy="16" r="13" fill="none"
            stroke="rgba(148,163,184,0.8)" strokeWidth="1.8"
            strokeDasharray="3 3"
          />
        )}
      </svg>
      {running && (
        <div className="absolute inset-0 flex items-center justify-center">
          <div className="w-1.5 h-1.5 rounded-full bg-primary animate-pulse" />
        </div>
      )}
    </div>
  )
}
