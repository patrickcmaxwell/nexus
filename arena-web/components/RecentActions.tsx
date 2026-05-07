"use client"

import { useState } from "react"
import { CheckCircle2, AlertCircle, Sparkles, Filter } from "lucide-react"

type Action = {
  id: string
  action: string
  caller: string | null
  status: string
  result: Record<string, unknown> | null
  error_msg: string | null
  created_at: string
}

export default function RecentActions({ actions }: { actions: Action[] }) {
  const [filter, setFilter] = useState<string>("all")

  const visible = filter === "all"
    ? actions
    : actions.filter((a) => a.action.startsWith(filter))

  const filters: Array<{ key: string; label: string }> = [
    { key: "all",     label: "All" },
    { key: "task",    label: "Tasks" },
    { key: "payment", label: "Payments" },
    { key: "sync",    label: "Sync" },
  ]

  return (
    <div className="flex flex-col">
      <div className="flex items-center gap-1 mb-3 p-1 bg-white/[0.04] border border-white/8 self-start">
        <Filter size={11} className="text-white/35 mx-1" />
        {filters.map((f) => (
          <button
            key={f.key}
            onClick={() => setFilter(f.key)}
            className="font-mono text-[9px] tracking-[0.15em] uppercase px-2 py-1"
            style={{
              color: filter === f.key ? "var(--arena-accent)" : "rgba(255,255,255,0.5)",
              background: filter === f.key ? "color-mix(in oklch, var(--arena-accent) 12%, transparent)" : "transparent",
              border: filter === f.key ? "1px solid color-mix(in oklch, var(--arena-accent) 40%, transparent)" : "1px solid transparent",
            }}
          >
            {f.label}
          </button>
        ))}
      </div>

      {visible.length === 0 ? (
        <p className="text-sm text-white/45 px-3 py-6">No actions yet. Connect a provider, then ask Eve to do something.</p>
      ) : (
        <ul className="flex flex-col gap-1">
          {visible.map((a) => {
            const mocked = (a.result as any)?.mocked === true
            return (
              <li key={a.id} className="flex items-center gap-3 px-3 py-2.5 bg-white/[0.025]">
                {a.status === "success" ? (
                  <CheckCircle2 size={14} className="text-emerald-400 shrink-0" />
                ) : (
                  <AlertCircle size={14} className="text-red-400 shrink-0" />
                )}
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="font-mono text-xs uppercase tracking-widest text-white/85">{a.action}</span>
                    {a.caller && (
                      <span className="font-mono text-[9px] tracking-widest uppercase text-white/40">via {a.caller}</span>
                    )}
                    {mocked && (
                      <span className="font-mono text-[9px] tracking-widest uppercase px-1.5 py-0.5 inline-flex items-center gap-1"
                        style={{ color: "rgb(252,211,77)", background: "rgba(252,211,77,0.1)", border: "1px solid rgba(252,211,77,0.4)" }}
                      >
                        <Sparkles size={9} /> mocked
                      </span>
                    )}
                  </div>
                  {a.error_msg && (
                    <p className="text-[11px] text-red-400/80 mt-0.5 truncate">{a.error_msg}</p>
                  )}
                  {!a.error_msg && (a.result as any)?.detail && (
                    <p className="text-[11px] text-white/45 mt-0.5 truncate">{String((a.result as any).detail)}</p>
                  )}
                </div>
                <span className="font-mono text-[9px] tracking-widest text-white/40 shrink-0">
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
