"use client"

import Link from "next/link"
import { Pin, Flag, ArrowRight } from "lucide-react"

type Record = {
  id: string
  operation_id: string
  operation_name: string
  title: string
  type: string
  status: string | null
  priority: string
  pinned: boolean
  updated_at: string
}

const TYPE_COLORS: Record<string, string> = {
  finding: "text-amber-400",
  intel: "text-primary",
  note: "text-muted-foreground",
  alert: "text-red-400",
  action: "text-emerald-400",
}

function timeAgo(iso: string) {
  const s = Math.floor((Date.now() - new Date(iso).getTime()) / 1000)
  if (s < 60) return `${s}s`
  if (s < 3600) return `${Math.floor(s / 60)}m`
  if (s < 86400) return `${Math.floor(s / 3600)}h`
  return `${Math.floor(s / 86400)}d`
}

export default function PinnedRecordsWidget({ records }: { records: Record[] }) {
  if (!records.length) return null

  return (
    <section className="rounded-xl border border-border bg-card overflow-hidden">
      <header className="flex items-center justify-between px-4 py-3 border-b border-amber-500/10">
        <div className="flex items-center gap-2">
          <div className="w-7 h-7 rounded-lg flex items-center justify-center bg-amber-500/10 border border-amber-500/20">
            <Pin size={13} className="text-amber-400" />
          </div>
          <div>
            <h2 className="text-[13px] font-semibold text-foreground">Pinned &amp; High Priority</h2>
            <p className="text-[10px] text-muted-foreground font-mono">
              {records.length} {records.length === 1 ? "record" : "records"} flagged for review
            </p>
          </div>
        </div>
        <Link
          href="/dashboard/operations"
          className="text-xs font-medium text-amber-400/70 hover:text-amber-400 transition-colors"
        >
          All records
        </Link>
      </header>

      <div className="divide-y divide-amber-500/5 max-h-[360px] overflow-y-auto">
        {records.map(r => {
          const isCritical = r.priority === "critical"
          return (
            <Link
              key={r.id}
              href={`/dashboard/operations?record=${r.id}`}
              className="flex items-start gap-3 px-4 py-3 hover:bg-amber-500/[0.04] transition-colors group"
            >
              <div className="flex-none mt-0.5">
                {r.pinned ? (
                  <Pin size={12} className="text-amber-400" fill="currentColor" />
                ) : (
                  <Flag size={12} className={isCritical ? "text-red-400" : "text-amber-400/70"} />
                )}
              </div>
              <div className="flex-1 min-w-0">
                <div className="flex items-baseline gap-2">
                  <span className="text-[13px] font-medium truncate text-foreground">{r.title}</span>
                  <span className={`text-xs font-medium flex-none ${TYPE_COLORS[r.type] ?? "text-muted-foreground"}`}>
                    {r.type}
                  </span>
                </div>
                <div className="flex items-center gap-2 mt-0.5 text-[10px] text-muted-foreground font-mono">
                  <span className="truncate">{r.operation_name}</span>
                  <span>·</span>
                  <span className={isCritical ? "text-red-400" : r.priority === "high" ? "text-amber-400/80" : ""}>
                    {r.priority}
                  </span>
                  {r.status && (
                    <>
                      <span>·</span>
                      <span>{r.status}</span>
                    </>
                  )}
                  <span className="ml-auto">{timeAgo(r.updated_at)}</span>
                </div>
              </div>
              <ArrowRight size={12} className="text-muted-foreground/40 group-hover:text-amber-400 transition-colors flex-none mt-1" />
            </Link>
          )
        })}
      </div>
    </section>
  )
}
