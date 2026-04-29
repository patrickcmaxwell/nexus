"use client"

import { useState, useEffect, useCallback } from "react"
import ReactMarkdown from "react-markdown"
import remarkGfm from "remark-gfm"
import {
  Sparkles, Loader2, RefreshCw, ChevronDown, ChevronRight,
  FileText, ListChecks, AlertTriangle, Layers3, ArrowRight, X,
} from "lucide-react"

type BriefKind = "summary" | "actions" | "contradictions" | "themes" | "next-steps"

interface Brief {
  id: string
  kind: BriefKind
  content: string
  generated_at: string
}

const KIND_META: Record<BriefKind, { label: string; icon: typeof FileText; description: string }> = {
  summary:        { label: "Operation Brief",  icon: FileText,        description: "Structured summary of state, progress, findings, open questions." },
  actions:        { label: "Action Items",     icon: ListChecks,      description: "Every task buried in records, extracted as a checklist." },
  contradictions: { label: "Contradictions",   icon: AlertTriangle,   description: "Disagreements between records and unresolved questions." },
  themes:         { label: "Themes",           icon: Layers3,         description: "Records clustered into themes so you can see what matters most." },
  "next-steps":   { label: "Next Steps",       icon: ArrowRight,      description: "Eve's ranked recommendations for what to do next." },
}

const KIND_ORDER: BriefKind[] = ["summary", "actions", "next-steps", "contradictions", "themes"]

function timeAgo(date: string) {
  const diff = Date.now() - new Date(date).getTime()
  const m = Math.floor(diff / 60000)
  if (m < 1) return "just now"
  if (m < 60) return `${m}m ago`
  const h = Math.floor(m / 60)
  if (h < 24) return `${h}h ago`
  return `${Math.floor(h / 24)}d ago`
}

interface Props {
  operationId: string
  recordCount: number
}

export default function OperationBriefs({ operationId, recordCount }: Props) {
  const [briefs, setBriefs] = useState<Partial<Record<BriefKind, Brief>>>({})
  const [loading, setLoading] = useState(true)
  const [expanded, setExpanded] = useState<BriefKind | null>(null)
  const [regenerating, setRegenerating] = useState<BriefKind | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [panelOpen, setPanelOpen] = useState(false)

  const load = useCallback(async () => {
    setLoading(true)
    const res = await fetch(`/api/operations/${operationId}/briefs`)
    if (res.ok) {
      const data = await res.json()
      setBriefs(data ?? {})
    }
    setLoading(false)
  }, [operationId])

  useEffect(() => {
    setBriefs({})
    setExpanded(null)
    setPanelOpen(false)
    load()
  }, [operationId, load])

  async function regenerate(kind: BriefKind) {
    setRegenerating(kind)
    setError(null)
    const res = await fetch(`/api/operations/${operationId}/briefs`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ kind }),
    })
    setRegenerating(null)
    if (!res.ok) {
      const err = await res.json().catch(() => ({}))
      setError(err.error || "Eve failed to produce that brief.")
      return
    }
    const brief: Brief = await res.json()
    setBriefs(prev => ({ ...prev, [kind]: brief }))
    setExpanded(kind)
  }

  async function dismiss(kind: BriefKind) {
    await fetch(`/api/operations/${operationId}/briefs`, {
      method: "DELETE",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ kind }),
    })
    setBriefs(prev => {
      const next = { ...prev }
      delete next[kind]
      return next
    })
    if (expanded === kind) setExpanded(null)
  }

  const existingKinds = KIND_ORDER.filter(k => briefs[k])

  return (
    <div className="border-b border-border bg-card/50">
      {/* Collapsed header */}
      <button
        onClick={() => setPanelOpen(v => !v)}
        className="w-full flex items-center justify-between px-4 md:px-6 py-2.5 hover:bg-muted/30 transition-colors"
      >
        <div className="flex items-center gap-2">
          <Sparkles size={13} className="text-accent" />
          <span className="text-[11px] font-mono uppercase tracking-widest text-foreground font-semibold">
            Eve Analyst
          </span>
          {!loading && existingKinds.length > 0 && (
            <span className="text-[10px] font-mono text-muted-foreground">
              · {existingKinds.length} brief{existingKinds.length === 1 ? "" : "s"} ready
            </span>
          )}
        </div>
        <ChevronDown
          size={14}
          className={`text-muted-foreground transition-transform ${panelOpen ? "rotate-180" : ""}`}
        />
      </button>

      {panelOpen && (
        <div className="px-4 md:px-6 pb-4 pt-1 space-y-2">
          {recordCount === 0 ? (
            <p className="text-xs text-muted-foreground italic">
              Add records to this operation before asking Eve to analyze them.
            </p>
          ) : (
            <>
              {/* Action chips for each analyst task */}
              <div className="flex flex-wrap gap-2">
                {KIND_ORDER.map(kind => {
                  const meta = KIND_META[kind]
                  const Icon = meta.icon
                  const existing = briefs[kind]
                  const isRegenerating = regenerating === kind
                  return (
                    <button
                      key={kind}
                      onClick={() => regenerate(kind)}
                      disabled={isRegenerating || regenerating !== null}
                      title={meta.description}
                      className={`flex items-center gap-1.5 text-[11px] font-medium border px-2.5 py-1.5 rounded-lg transition-colors disabled:opacity-60 ${
                        existing
                          ? "border-accent/40 bg-accent/5 text-accent hover:bg-accent/10"
                          : "border-border text-foreground hover:border-accent/30 hover:bg-accent/5"
                      }`}
                    >
                      {isRegenerating ? <Loader2 size={11} className="animate-spin" /> : <Icon size={11} />}
                      {meta.label}
                      {existing && !isRegenerating && (
                        <RefreshCw size={9} className="opacity-60" />
                      )}
                    </button>
                  )
                })}
              </div>

              {error && <p className="text-xs text-destructive">{error}</p>}

              {/* Existing brief cards */}
              {existingKinds.length > 0 && (
                <div className="space-y-2 pt-1">
                  {existingKinds.map(kind => {
                    const brief = briefs[kind]!
                    const meta = KIND_META[kind]
                    const Icon = meta.icon
                    const isExpanded = expanded === kind
                    return (
                      <div key={kind} className="border border-border rounded-lg overflow-hidden bg-background">
                        <div className="flex items-center gap-2 px-3 py-2 border-b border-border/50">
                          <button
                            onClick={() => setExpanded(isExpanded ? null : kind)}
                            className="flex items-center gap-2 flex-1 min-w-0 text-left"
                          >
                            {isExpanded ? <ChevronDown size={12} className="text-muted-foreground flex-shrink-0" /> : <ChevronRight size={12} className="text-muted-foreground flex-shrink-0" />}
                            <Icon size={12} className="text-accent flex-shrink-0" />
                            <span className="text-xs font-semibold text-foreground truncate">{meta.label}</span>
                            <span className="text-[10px] text-muted-foreground ml-auto flex-shrink-0">
                              {timeAgo(brief.generated_at)}
                            </span>
                          </button>
                          <button
                            onClick={() => dismiss(kind)}
                            title="Dismiss"
                            className="p-1 text-muted-foreground hover:text-destructive transition-colors"
                          >
                            <X size={12} />
                          </button>
                        </div>
                        {isExpanded && (
                          <div className="px-4 py-3 prose prose-sm dark:prose-invert max-w-none leading-relaxed
                            prose-headings:text-foreground prose-headings:font-semibold
                            prose-h1:text-sm prose-h2:text-sm prose-h3:text-xs
                            prose-p:text-foreground prose-p:my-1.5
                            prose-strong:text-foreground
                            prose-a:text-accent prose-a:no-underline hover:prose-a:underline
                            prose-code:text-accent prose-code:bg-accent/10 prose-code:px-1 prose-code:py-0.5 prose-code:rounded prose-code:text-xs prose-code:before:content-none prose-code:after:content-none
                            prose-li:text-foreground prose-li:my-0.5 prose-li:marker:text-accent
                            prose-hr:border-border
                          ">
                            <ReactMarkdown remarkPlugins={[remarkGfm]}>{brief.content}</ReactMarkdown>
                          </div>
                        )}
                      </div>
                    )
                  })}
                </div>
              )}

              {loading && existingKinds.length === 0 && (
                <p className="text-xs text-muted-foreground">Checking for saved briefs…</p>
              )}
            </>
          )}
        </div>
      )}
    </div>
  )
}
