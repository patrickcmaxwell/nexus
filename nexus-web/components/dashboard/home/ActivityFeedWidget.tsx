"use client"

import { useState } from "react"
import type React from "react"
import Link from "next/link"
import { Activity, FileText, Telescope, MessageSquare, CheckCircle2, AlertTriangle, X, ChevronRight } from "lucide-react"
import type { ComponentType } from "react"

type Item = {
  id: string
  kind: "record_created" | "research_completed" | "research_started" | "brief_generated" | "conversation"
  title: string
  subtitle: string
  at: string
  href: string
  accent: string
}

const KIND_ICON: Record<Item["kind"], ComponentType<{ size?: number; className?: string; style?: React.CSSProperties }>> = {
  record_created:      FileText,
  research_completed:  CheckCircle2,
  research_started:    Telescope,
  brief_generated:     Activity,
  conversation:        MessageSquare,
}

const KIND_LABEL: Record<Item["kind"], string> = {
  record_created:      "Record",
  research_completed:  "Research",
  research_started:    "Research",
  brief_generated:     "Intel",
  conversation:        "Convo",
}

type Filter = "all" | "record_created" | "research" | "brief_generated" | "conversation"

const FILTERS: { id: Filter; label: string }[] = [
  { id: "all",            label: "All" },
  { id: "record_created", label: "Records" },
  { id: "research",       label: "Research" },
  { id: "brief_generated",label: "Intel" },
  { id: "conversation",   label: "Convos" },
]

function timeAgo(iso: string) {
  const s = Math.floor((Date.now() - new Date(iso).getTime()) / 1000)
  if (s < 60) return "just now"
  if (s < 3600) return `${Math.floor(s / 60)}m ago`
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`
  if (s < 604800) return `${Math.floor(s / 86400)}d ago`
  return new Date(iso).toLocaleDateString()
}

function matchesFilter(item: Item, filter: Filter) {
  if (filter === "all") return true
  if (filter === "research") return item.kind === "research_started" || item.kind === "research_completed"
  return item.kind === filter
}

// ── Activity Log Modal ────────────────────────────────────────────────────────
function ActivityModal({ activity, onClose }: { activity: Item[]; onClose: () => void }) {
  const [filter, setFilter] = useState<Filter>("all")
  const visible = activity.filter(i => matchesFilter(i, filter))

  return (
    <>
      <style>{`
        @keyframes modal-in {
          from { opacity: 0; transform: translateY(12px) scale(0.98); }
          to   { opacity: 1; transform: translateY(0)   scale(1); }
        }
        .activity-modal { animation: modal-in 0.2s ease-out forwards; }
      `}</style>

      {/* Backdrop */}
      <div
        className="fixed inset-0 z-50 flex items-center justify-center p-4"
        style={{ background: "rgba(0,0,0,0.75)", backdropFilter: "blur(6px)" }}
        onClick={onClose}
      >
        {/* Panel */}
        <div
          className="activity-modal relative w-full flex flex-col"
          style={{
            maxWidth: 680,
            maxHeight: "85vh",
            background: "#0a0a0a",
            border: "1px solid rgba(0,200,255,0.15)",
            borderRadius: 12,
            fontFamily: "'SF Mono', monospace",
            overflow: "hidden",
          }}
          onClick={e => e.stopPropagation()}
        >
          {/* Header */}
          <div
            className="flex-none flex items-center justify-between px-6 py-4"
            style={{ borderBottom: "1px solid rgba(0,200,255,0.1)" }}
          >
            <div className="flex items-center gap-3">
              <span style={{ color: "#00c8ff", letterSpacing: "6px", fontSize: "11px", fontWeight: 300 }}>
                ACTIVITY LOG
              </span>
              <span
                className="px-2 py-0.5 rounded"
                style={{ background: "rgba(0,200,255,0.08)", color: "rgba(0,200,255,0.6)", fontSize: "9px", letterSpacing: "2px" }}
              >
                {activity.length}
              </span>
            </div>
            <button
              onClick={onClose}
              className="p-1.5 rounded transition-opacity hover:opacity-70"
              style={{ color: "rgba(255,255,255,0.35)" }}
            >
              <X size={14} />
            </button>
          </div>

          {/* Filters */}
          <div
            className="flex-none flex items-center gap-1 px-6 py-3"
            style={{ borderBottom: "1px solid rgba(255,255,255,0.05)" }}
          >
            {FILTERS.map(f => (
              <button
                key={f.id}
                onClick={() => setFilter(f.id)}
                className="px-3 py-1 rounded transition-all"
                style={{
                  fontSize: "9px",
                  letterSpacing: "2.5px",
                  border: filter === f.id
                    ? "1px solid rgba(0,200,255,0.4)"
                    : "1px solid rgba(255,255,255,0.06)",
                  color: filter === f.id ? "#00c8ff" : "rgba(255,255,255,0.35)",
                  background: filter === f.id ? "rgba(0,200,255,0.07)" : "transparent",
                }}
              >
                {f.label.toUpperCase()}
              </button>
            ))}
            <span className="ml-auto" style={{ color: "rgba(255,255,255,0.2)", fontSize: "9px", letterSpacing: "2px" }}>
              {visible.length} EVENTS
            </span>
          </div>

          {/* List */}
          <div className="flex-1 overflow-y-auto">
            {visible.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-20 gap-3">
                <AlertTriangle size={24} style={{ color: "rgba(255,255,255,0.1)" }} />
                <span style={{ color: "rgba(255,255,255,0.25)", fontSize: "10px", letterSpacing: "3px" }}>
                  NO EVENTS
                </span>
              </div>
            ) : (
              <ol className="relative">
                {/* Timeline spine */}
                <div
                  className="absolute top-4 bottom-4"
                  style={{ left: 33, width: 1, background: "rgba(0,200,255,0.08)" }}
                  aria-hidden
                />
                {visible.map((item, idx) => {
                  const Icon = KIND_ICON[item.kind]
                  const isFirst = idx === 0
                  return (
                    <li key={item.id}>
                      <Link
                        href={item.href}
                        onClick={onClose}
                        className="group flex items-start gap-4 px-6 py-3 transition-colors"
                        style={{ background: "transparent" }}
                        onMouseEnter={e => (e.currentTarget.style.background = "rgba(0,200,255,0.04)")}
                        onMouseLeave={e => (e.currentTarget.style.background = "transparent")}
                      >
                        {/* Node */}
                        <div
                          className="relative z-10 flex-none flex items-center justify-center rounded-full"
                          style={{
                            width: 18, height: 18,
                            background: item.accent,
                            boxShadow: "0 0 0 3px #0a0a0a",
                            marginTop: 2,
                          }}
                        >
                          <Icon size={9} style={{ color: "#000" }} />
                        </div>

                        {/* Content */}
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-2">
                            <span
                              className="text-[12px] font-medium truncate transition-colors"
                              style={{ color: "rgba(255,255,255,0.8)" }}
                            >
                              {item.title}
                            </span>
                            {isFirst && (
                              <span
                                className="flex-none px-1.5 py-0.5 rounded"
                                style={{ background: "rgba(0,200,255,0.12)", color: "#00c8ff", fontSize: "8px", letterSpacing: "2px" }}
                              >
                                NEW
                              </span>
                            )}
                          </div>
                          <p className="text-[11px] truncate" style={{ color: "rgba(255,255,255,0.35)" }}>
                            {item.subtitle}
                          </p>
                        </div>

                        {/* Meta */}
                        <div className="flex-none flex flex-col items-end gap-1">
                          <span style={{ color: "rgba(255,255,255,0.25)", fontSize: "9px", letterSpacing: "2px" }}>
                            {timeAgo(item.at)}
                          </span>
                          <span
                            className="px-1.5 py-0.5 rounded"
                            style={{ background: "rgba(255,255,255,0.05)", color: "rgba(255,255,255,0.3)", fontSize: "8px", letterSpacing: "1.5px" }}
                          >
                            {KIND_LABEL[item.kind].toUpperCase()}
                          </span>
                        </div>

                        <ChevronRight size={12} style={{ color: "rgba(0,200,255,0)", marginTop: 4, flexShrink: 0, transition: "color 0.15s" }} className="group-hover:!text-primary/40" />
                      </Link>
                    </li>
                  )
                })}
              </ol>
            )}
          </div>

          {/* Footer */}
          <div
            className="flex-none px-6 py-3 flex items-center justify-between"
            style={{ borderTop: "1px solid rgba(255,255,255,0.05)", color: "rgba(255,255,255,0.2)", fontSize: "9px", letterSpacing: "2px" }}
          >
            <span>NEXUS ACTIVITY LOG</span>
            <span>ESC TO CLOSE</span>
          </div>
        </div>
      </div>
    </>
  )
}

// ── Widget (compact inline view) ──────────────────────────────────────────────
export default function ActivityFeedWidget({ activity }: { activity: Item[] }) {
  const [open, setOpen] = useState(false)
  const preview = activity.slice(0, 3)

  return (
    <>
      {open && <ActivityModal activity={activity} onClose={() => setOpen(false)} />}

      <section className="rounded-xl border border-border bg-card overflow-hidden">
        <header className="flex items-center justify-between px-4 py-3 border-b border-border">
          <div className="flex items-center gap-2">
            <div className="w-7 h-7 rounded-lg flex items-center justify-center bg-secondary border border-border">
              <Activity size={13} className="text-muted-foreground" />
            </div>
            <div>
              <h2 className="text-[13px] font-semibold text-foreground">Activity</h2>
              <p className="text-[10px] text-muted-foreground font-mono">Latest system events</p>
            </div>
          </div>

          <button
            onClick={() => setOpen(true)}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium border transition-colors hover:border-accent/40 hover:text-accent"
            style={{ borderColor: "rgba(255,255,255,0.08)", color: "rgba(255,255,255,0.4)" }}
          >
            {activity.length > 0 && (
              <span
                className="w-4 h-4 rounded-full flex items-center justify-center text-[8px]"
                style={{ background: "rgba(0,200,255,0.15)", color: "#00c8ff" }}
              >
                {activity.length > 9 ? "9+" : activity.length}
              </span>
            )}
            View Log
            <ChevronRight size={10} />
          </button>
        </header>

        {activity.length === 0 ? (
          <div className="py-8 text-center">
            <AlertTriangle size={24} className="mx-auto mb-2 text-muted-foreground/20" />
            <p className="text-xs text-muted-foreground">No recent activity</p>
          </div>
        ) : (
          <ol className="relative">
            <div className="absolute left-[22px] top-2 bottom-2 w-px bg-border/50" aria-hidden />
            {preview.map((item, idx) => {
              const Icon = KIND_ICON[item.kind]
              return (
                <li key={item.id} className="relative">
                  <Link
                    href={item.href}
                    className="flex items-start gap-3 px-4 py-2.5 hover:bg-secondary/50 transition-colors group"
                  >
                    <div
                      className="relative z-10 flex-none w-[14px] h-[14px] rounded-full flex items-center justify-center ring-2 ring-background"
                      style={{ background: item.accent }}
                    >
                      <Icon size={8} className="text-background" />
                    </div>
                    <div className="flex-1 min-w-0 -mt-0.5">
                      <div className="flex items-baseline gap-2">
                        <span className="text-[12px] font-medium truncate text-foreground group-hover:text-accent transition-colors">
                          {item.title}
                        </span>
                        <span className="ml-auto flex-none font-mono text-[9px] text-muted-foreground/60 uppercase tracking-widest">
                          {timeAgo(item.at)}
                        </span>
                      </div>
                      <p className="text-[11px] text-muted-foreground truncate">{item.subtitle}</p>
                    </div>
                  </Link>
                </li>
              )
            })}

            {activity.length > 3 && (
              <li>
                <button
                  onClick={() => setOpen(true)}
                  className="w-full flex items-center justify-center gap-1.5 py-2.5 text-xs font-medium text-muted-foreground hover:text-accent transition-colors border-t border-border/50"
                >
                  +{activity.length - 3} more events
                  <ChevronRight size={10} />
                </button>
              </li>
            )}
          </ol>
        )}
      </section>
    </>
  )
}
