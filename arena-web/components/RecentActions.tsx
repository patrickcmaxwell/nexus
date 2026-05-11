"use client"

// Recent action log. Clean Apple/Linear baseline — sentence case, soft
// status pills, single accent. No HUD chrome.

import { useState } from "react"
import { CheckCircle2, AlertCircle, Sparkles } from "lucide-react"

type Action = {
  id: string
  action: string
  caller: string | null
  status: string
  result: Record<string, unknown> | null
  error_msg: string | null
  created_at: string
}

const FILTERS: Array<{ key: string; label: string }> = [
  { key: "all",     label: "All" },
  { key: "task",    label: "Tasks" },
  { key: "payment", label: "Payments" },
  { key: "sync",    label: "Sync" },
  { key: "inbound", label: "Inbound" },
]

export default function RecentActions({ actions }: { actions: Action[] }) {
  const [filter, setFilter] = useState<string>("all")

  const visible = filter === "all"
    ? actions
    : actions.filter((a) => a.action.startsWith(filter))

  return (
    <div className="rounded-[14px] bg-[color:var(--color-surface)] border border-[color:var(--color-border)] overflow-hidden">
      <div className="flex items-center gap-1 px-3 py-2 border-b border-[color:var(--color-border)] bg-[color:var(--color-bg)]/40">
        {FILTERS.map((f) => (
          <button
            key={f.key}
            onClick={() => setFilter(f.key)}
            className={`text-xs px-2.5 py-1.5 rounded-md transition-colors ${
              filter === f.key
                ? "bg-[color:var(--color-accent-soft)] text-[color:var(--color-accent)]"
                : "text-[color:var(--color-fg-muted)] hover:text-[color:var(--color-fg)] hover:bg-[color:var(--color-surface-2)]"
            }`}
          >
            {f.label}
          </button>
        ))}
      </div>

      {visible.length === 0 ? (
        <p className="text-sm text-[color:var(--color-fg-muted)] px-5 py-8 text-center">
          {actions.length === 0
            ? "No actions yet. Connect a provider, then ask Eve to do something."
            : "No actions match this filter."}
        </p>
      ) : (
        <ul className="divide-y divide-[color:var(--color-border)]">
          {visible.map((a) => {
            const mocked = (a.result as { mocked?: boolean } | null)?.mocked === true
            const detail = (a.result as { detail?: string } | null)?.detail
            return (
              <li key={a.id} className="flex items-start gap-3 px-5 py-3 hover:bg-[color:var(--color-surface-2)]/50 transition-colors">
                {a.status === "success" ? (
                  <CheckCircle2 size={15} className="text-[color:var(--color-success)] flex-shrink-0 mt-0.5" />
                ) : (
                  <AlertCircle size={15} className="text-[color:var(--color-danger)] flex-shrink-0 mt-0.5" />
                )}
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="text-sm text-[color:var(--color-fg)]">{a.action}</span>
                    {a.caller && (
                      <span className="text-xs text-[color:var(--color-fg-subtle)]">via {a.caller}</span>
                    )}
                    {mocked && (
                      <span className="text-xs px-1.5 py-0.5 rounded bg-[color:var(--color-warning)]/15 text-[color:var(--color-warning)] inline-flex items-center gap-1">
                        <Sparkles size={10} /> mocked
                      </span>
                    )}
                  </div>
                  {a.error_msg && (
                    <p className="text-xs text-[color:var(--color-danger)]/85 mt-1 truncate">{a.error_msg}</p>
                  )}
                  {!a.error_msg && detail && (
                    <p className="text-xs text-[color:var(--color-fg-muted)] mt-1 truncate">{String(detail)}</p>
                  )}
                </div>
                <span className="text-xs text-[color:var(--color-fg-subtle)] flex-shrink-0 mt-0.5">
                  {relative(a.created_at)}
                </span>
              </li>
            )
          })}
        </ul>
      )}
    </div>
  )
}

function relative(iso: string): string {
  const ms = Date.now() - new Date(iso).getTime()
  const m = Math.round(ms / 60000)
  if (m < 1) return "just now"
  if (m < 60) return `${m}m ago`
  const h = Math.round(m / 60)
  if (h < 24) return `${h}h ago`
  const d = Math.round(h / 24)
  return `${d}d ago`
}
