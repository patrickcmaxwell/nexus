"use client"

import { Bolt, ListChecks, CreditCard, RefreshCw, AlertTriangle, ChevronRight } from "lucide-react"
import type { ComponentType } from "react"

type Entry = {
  id: string
  action: string
  caller: string | null
  payload: Record<string, unknown>
  result: Record<string, unknown>
  status: string
  created_at: string
}

const ICON_FOR: Record<string, ComponentType<{ size?: number; className?: string }>> = {
  "task/create":   ListChecks,
  "task/update":   ListChecks,
  "payment/route": CreditCard,
  "sync/push":     RefreshCw,
}

const ACCENT_FOR: Record<string, string> = {
  "task/create":   "#00ff88",
  "task/update":   "#00d4ff",
  "payment/route": "#ffb800",
  "sync/push":     "#a06bff",
}

function timeAgo(iso: string) {
  const s = Math.floor((Date.now() - new Date(iso).getTime()) / 1000)
  if (s < 60) return "just now"
  if (s < 3600) return `${Math.floor(s / 60)}m ago`
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`
  if (s < 604800) return `${Math.floor(s / 86400)}d ago`
  return new Date(iso).toLocaleDateString()
}

function summary(entry: Entry): string {
  const a = entry.action
  const p = entry.payload || {}
  const r = entry.result || {}
  const title = (p as { title?: string }).title
  const taskId = (r as { task_id?: string }).task_id
  switch (a) {
    case "task/create":   return title ? `Created "${title}"` + (taskId ? ` (${taskId})` : "") : "Created task"
    case "task/update":   return `Updated task ${(p as { task_id?: string }).task_id ?? ""}`.trim()
    case "payment/route": {
      const amount = (p as { amount?: number }).amount
      const currency = (p as { currency?: string }).currency ?? "USD"
      return amount != null ? `Routed ${currency} ${amount}` : "Routed payment"
    }
    case "sync/push":     return "Pushed memory bundle to phone"
    default:              return a
  }
}

export default function ArenaActivityWidget({ entries }: { entries: Entry[] }) {
  const visible = entries.slice(0, 5)

  return (
    <section className="rounded-xl border border-border bg-card/30 overflow-hidden">
      <header className="flex items-center justify-between px-4 py-3 border-b border-border">
        <div className="flex items-center gap-2">
          <div className="w-7 h-7 rounded-lg flex items-center justify-center bg-secondary border border-border">
            <Bolt size={13} className="text-muted-foreground" />
          </div>
          <div>
            <h2 className="text-[13px] font-semibold text-foreground">Arena</h2>
            <p className="text-[10px] text-muted-foreground font-mono">Real-world actions Eve has executed</p>
          </div>
        </div>
        <span
          className="px-2 py-0.5 rounded font-mono text-[9px] uppercase tracking-widest"
          style={{ background: "rgba(255,255,255,0.04)", color: "rgba(255,255,255,0.4)" }}
        >
          {entries.length}
        </span>
      </header>

      {entries.length === 0 ? (
        <div className="py-8 text-center">
          <AlertTriangle size={24} className="mx-auto mb-2 text-muted-foreground/20" />
          <p className="text-xs text-muted-foreground">No Arena actions yet.</p>
          <p className="text-[10px] font-mono text-muted-foreground/60 mt-1">Ask Eve to create a task or sync.</p>
        </div>
      ) : (
        <ol>
          {visible.map((entry) => {
            const Icon = ICON_FOR[entry.action] ?? Bolt
            const accent = ACCENT_FOR[entry.action] ?? "#888"
            const failed = entry.status !== "success"
            return (
              <li key={entry.id} className="border-b border-border/40 last:border-0">
                <div className="flex items-start gap-3 px-4 py-2.5">
                  <div
                    className="flex-none w-[18px] h-[18px] rounded-full flex items-center justify-center"
                    style={{ background: failed ? "#ff4444" : accent, marginTop: 2 }}
                  >
                    <Icon size={9} className="text-background" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-baseline gap-2">
                      <span className="text-[12px] font-medium truncate text-foreground">
                        {summary(entry)}
                      </span>
                      <span className="ml-auto flex-none font-mono text-[9px] text-muted-foreground/60 uppercase tracking-widest">
                        {timeAgo(entry.created_at)}
                      </span>
                    </div>
                    <p className="text-[10px] font-mono text-muted-foreground/60">
                      <span className="uppercase tracking-widest">{entry.action}</span>
                      {entry.caller && (
                        <>
                          {"  ·  "}
                          <span style={{ color: entry.caller === "eve" ? "#a06bff" : "rgba(255,255,255,0.3)" }}>
                            via {entry.caller}
                          </span>
                        </>
                      )}
                      {failed && (
                        <>
                          {"  ·  "}
                          <span style={{ color: "#ff4444" }}>FAILED</span>
                        </>
                      )}
                    </p>
                  </div>
                </div>
              </li>
            )
          })}
        </ol>
      )}
    </section>
  )
}
