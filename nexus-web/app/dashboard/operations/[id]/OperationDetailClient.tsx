"use client"

// Per-operation detail. Tabs for Overview / Records / Briefs.

import { useState } from "react"
import Link from "next/link"
import { Calendar, Tag } from "lucide-react"
import { Card, Pill, Section, Tabs, EmptyState } from "@/components/ui/primitives"

type Operation = {
  id: string
  name: string
  codename: string | null
  description: string | null
  objectives: string | null
  directives: string | null
  status: string
  priority: string
  tags: string[] | null
  created_at: string
  updated_at: string
}

type Record_ = {
  id: string
  title: string
  content: string
  type: string
  status: string | null
  priority: string
  created_at: string
  updated_at: string
}

type Brief = {
  id: string
  kind: string
  content: string
  generated_at: string
}

const STATUS_TONE: Record<string, "success" | "warning" | "danger" | "muted" | "neutral"> = {
  active: "success",
  planning: "warning",
  paused: "muted",
  complete: "neutral",
  aborted: "danger",
}

const PRIORITY_TONE: Record<string, "danger" | "warning" | "neutral" | "muted"> = {
  critical: "danger",
  high:     "warning",
  medium:   "neutral",
  low:      "muted",
}

export default function OperationDetailClient({
  operation, records, briefs,
}: {
  operation: Operation
  records: Record_[]
  briefs: Brief[]
}) {
  const [tab, setTab] = useState("overview")

  return (
    <>
      <header className="mb-8">
        <div className="flex items-center gap-3 flex-wrap">
          <h1 className="text-2xl font-semibold tracking-tight text-foreground">{operation.name}</h1>
          {operation.codename && <span className="text-sm font-mono text-accent">// {operation.codename}</span>}
          <Pill tone={STATUS_TONE[operation.status] ?? "muted"}>{operation.status}</Pill>
          <Pill tone={PRIORITY_TONE[operation.priority] ?? "muted"}>{operation.priority}</Pill>
        </div>
        {operation.description && (
          <p className="text-sm text-muted-foreground mt-3 max-w-2xl leading-relaxed">{operation.description}</p>
        )}
        <div className="flex items-center gap-3 mt-3 text-xs text-muted-foreground flex-wrap">
          <span className="flex items-center gap-1.5"><Calendar size={12} /> Updated {timeAgo(operation.updated_at)}</span>
          {operation.tags && operation.tags.length > 0 && (
            <span className="flex items-center gap-1.5">
              <Tag size={12} />
              {operation.tags.join(", ")}
            </span>
          )}
        </div>
      </header>

      <Tabs
        active={tab}
        onChange={setTab}
        tabs={[
          { id: "overview", label: "Overview" },
          { id: "records", label: `Records (${records.length})` },
          { id: "briefs", label: `Briefs (${briefs.length})` },
        ]}
        className="mb-6"
      />

      {tab === "overview" && (
        <div className="space-y-4">
          {operation.objectives && (
            <Card>
              <Section title="Objectives">
                <p className="text-sm text-foreground/90 mt-3 leading-relaxed whitespace-pre-wrap">{operation.objectives}</p>
              </Section>
            </Card>
          )}

          {operation.directives && (
            <Card>
              <Section title="Directives" description="Rules Eve and the assigned agents operate by.">
                <p className="text-sm text-foreground/90 mt-3 leading-relaxed whitespace-pre-wrap">{operation.directives}</p>
              </Section>
            </Card>
          )}

          {!operation.objectives && !operation.directives && (
            <Card>
              <EmptyState title="No objectives or directives set" description="Add some on the Operations page to give Eve and your agents context." />
            </Card>
          )}
        </div>
      )}

      {tab === "records" && (
        <Card padding="none">
          {records.length === 0 ? (
            <EmptyState title="No records" description="Records track findings, intel, and decisions. Add one from the Operations page." />
          ) : (
            <ul className="divide-y divide-border">
              {records.map(r => (
                <li key={r.id} className="px-5 py-4 hover:bg-muted/40 transition-colors">
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-2 flex-wrap">
                        <p className="text-sm font-medium text-foreground">{r.title}</p>
                        <Pill tone="muted" size="xs">{r.type}</Pill>
                        {r.status && <Pill tone="muted" size="xs">{r.status}</Pill>}
                      </div>
                      {r.content && (
                        <p className="text-sm text-muted-foreground mt-1.5 line-clamp-2">{r.content}</p>
                      )}
                    </div>
                    <span className="text-xs text-muted-foreground flex-shrink-0">{timeAgo(r.updated_at)}</span>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </Card>
      )}

      {tab === "briefs" && (
        <div className="space-y-3">
          {briefs.length === 0 ? (
            <Card>
              <EmptyState title="No briefs yet" description="Briefs are Eve's analyst summaries — generate one from the Operations page or schedule a recurring one in Calendar." />
            </Card>
          ) : (
            briefs.map(b => (
              <Card key={b.id}>
                <div className="flex items-center justify-between mb-2">
                  <p className="text-sm font-medium text-foreground capitalize">{b.kind.replace(/-/g, " ")}</p>
                  <span className="text-xs text-muted-foreground">{timeAgo(b.generated_at)}</span>
                </div>
                <div className="prose prose-sm prose-invert max-w-none text-sm text-foreground/90 leading-relaxed whitespace-pre-wrap">
                  {b.content}
                </div>
              </Card>
            ))
          )}
        </div>
      )}

      <div className="mt-8 pt-6 border-t border-border flex items-center justify-between text-xs text-muted-foreground">
        <span>Created {new Date(operation.created_at).toLocaleDateString()}</span>
        <Link href={`/dashboard/operations`} className="hover:text-foreground transition-colors">
          Back to all operations →
        </Link>
      </div>
    </>
  )
}

function timeAgo(iso: string): string {
  const ms = Date.now() - new Date(iso).getTime()
  const m = Math.round(ms / 60000)
  if (m < 1) return "just now"
  if (m < 60) return `${m}m ago`
  const h = Math.round(m / 60)
  if (h < 24) return `${h}h ago`
  const d = Math.round(h / 24)
  return `${d}d ago`
}
