"use client"

import Link from "next/link"
import { Zap, ArrowRight } from "lucide-react"

type Item = {
  id: string
  brief_id: string
  operation_id: string
  operation_name: string
  kind: "actions" | "next_steps"
  text: string
  generated_at: string
}

export default function ActionItemsWidget({ items }: { items: Item[] }) {
  if (!items.length) return null

  // Group by operation so the user sees "this op needs X, Y, Z; that op needs A, B"
  const byOp = new Map<string, { operation_id: string; operation_name: string; items: Item[] }>()
  for (const it of items) {
    const existing = byOp.get(it.operation_id)
    if (existing) existing.items.push(it)
    else byOp.set(it.operation_id, { operation_id: it.operation_id, operation_name: it.operation_name, items: [it] })
  }

  return (
    <section className="rounded-xl border border-border bg-card overflow-hidden">
      <header className="flex items-center justify-between px-4 py-3 border-b border-emerald-500/10">
        <div className="flex items-center gap-2">
          <div className="w-7 h-7 rounded-lg flex items-center justify-center bg-emerald-500/10 border border-emerald-500/20">
            <Zap size={13} className="text-emerald-400" />
          </div>
          <div>
            <h2 className="text-[13px] font-semibold text-foreground">Eve&apos;s Recommendations</h2>
            <p className="text-[10px] text-muted-foreground font-mono">
              {items.length} action {items.length === 1 ? "item" : "items"} from recent briefs
            </p>
          </div>
        </div>
      </header>

      <div className="divide-y divide-emerald-500/5">
        {Array.from(byOp.values()).map(group => (
          <div key={group.operation_id} className="px-4 py-3">
            <Link
              href="/dashboard/operations"
              className="flex items-center gap-1 text-xs font-medium text-emerald-400/70 hover:text-emerald-400 transition-colors mb-2"
            >
              {group.operation_name} <ArrowRight size={9} />
            </Link>
            <ul className="space-y-1.5">
              {group.items.slice(0, 4).map(it => (
                <li key={it.id} className="flex items-start gap-2 text-[12px] text-foreground/90 leading-relaxed">
                  <span
                    className="flex-none mt-1 w-1 h-1 rounded-full"
                    style={{ background: it.kind === "actions" ? "#10b981" : "#34d399" }}
                  />
                  <span className="flex-1">{it.text}</span>
                  <span className="flex-none font-mono text-[8px] uppercase tracking-widest text-muted-foreground/60 mt-0.5">
                    {it.kind === "actions" ? "action" : "next"}
                  </span>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </div>
    </section>
  )
}
