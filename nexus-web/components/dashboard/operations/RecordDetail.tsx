"use client"

import { useState, useEffect, useCallback, useRef } from "react"
import { useRouter } from "next/navigation"
import ReactMarkdown from "react-markdown"
import remarkGfm from "remark-gfm"
import {
  X, Pencil, Save, Star, Archive, Trash2, Check, MessageSquare,
  FlaskConical, Loader2, AlertTriangle, ChevronDown, ChevronRight,
  Clock, Circle, PlayCircle, CheckCircle2, CircleSlash,
} from "lucide-react"

// ── Types ────────────────────────────────────────────────────────────────────

export type RecordStatus = "open" | "doing" | "done" | "blocked" | null
export type RecordType = "note" | "intel" | "data" | "finding" | "alert" | "file"

export interface FullRecord {
  id: string
  operation_id: string
  parent_record_id: string | null
  type: RecordType
  title: string
  content: string
  source: string
  priority: string
  status: RecordStatus
  pinned: boolean
  archived_at: string | null
  source_conversation_id: string | null
  source_message_id: string | null
  created_at: string
  updated_at: string | null
}

interface ChildRecord {
  id: string
  title: string
  type: RecordType
  content: string
  created_at: string
  status: RecordStatus
  pinned: boolean
}

interface ResearchJob {
  id: string
  status: "queued" | "running" | "completed" | "failed"
  prompt: string | null
  model: string | null
  started_at: string | null
  completed_at: string | null
  error: string | null
  progress_note: string | null
}

interface Props {
  recordId: string
  onClose: () => void
  onChanged: () => void
}

// ── Status config ────────────────────────────────────────────────────────────

const STATUS_ORDER: Exclude<RecordStatus, null>[] = ["open", "doing", "done", "blocked"]

const STATUS_META: Record<Exclude<RecordStatus, null>, { label: string; icon: typeof Circle; className: string }> = {
  open:    { label: "Open",    icon: Circle,        className: "text-muted-foreground border-border" },
  doing:   { label: "Doing",   icon: PlayCircle,    className: "text-accent border-accent/50 bg-accent/10" },
  done:    { label: "Done",    icon: CheckCircle2,  className: "text-green-400 border-green-400/40 bg-green-400/10" },
  blocked: { label: "Blocked", icon: CircleSlash,   className: "text-destructive border-destructive/40 bg-destructive/10" },
}

const TYPE_OPTIONS: RecordType[] = ["note", "intel", "data", "finding", "alert", "file"]

function timeAgo(date: string) {
  const diff = Date.now() - new Date(date).getTime()
  const m = Math.floor(diff / 60000)
  if (m < 1) return "just now"
  if (m < 60) return `${m}m ago`
  const h = Math.floor(m / 60)
  if (h < 24) return `${h}h ago`
  return `${Math.floor(h / 24)}d ago`
}

// ── Main Component ───────────────────────────────────────────────────────────

export default function RecordDetail({ recordId, onClose, onChanged }: Props) {
  const router = useRouter()

  const [record, setRecord] = useState<FullRecord | null>(null)
  const [children, setChildren] = useState<ChildRecord[]>([])
  const [latestResearch, setLatestResearch] = useState<ResearchJob | null>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // Edit mode for content/title
  const [editing, setEditing] = useState(false)
  const [editTitle, setEditTitle] = useState("")
  const [editContent, setEditContent] = useState("")
  const [editType, setEditType] = useState<RecordType>("note")
  const [editPriority, setEditPriority] = useState("normal")

  // Research prompt UI
  const [researchOpen, setResearchOpen] = useState(false)
  const [researchPrompt, setResearchPrompt] = useState("")
  const [startingResearch, setStartingResearch] = useState(false)

  // Expanded child record previews
  const [expandedChildren, setExpandedChildren] = useState<Set<string>>(new Set())

  const pollRef = useRef<NodeJS.Timeout | null>(null)

  // ── Load / reload ────────────────────────────────────────────────────────

  const load = useCallback(async () => {
    setError(null)
    const res = await fetch(`/api/operations/records/${recordId}`)
    if (!res.ok) {
      setError("Failed to load record.")
      setLoading(false)
      return
    }
    const data = await res.json()
    setRecord(data.record)
    setChildren(data.children ?? [])
    setLatestResearch(data.latestResearch ?? null)
    setEditTitle(data.record.title)
    setEditContent(data.record.content ?? "")
    setEditType(data.record.type)
    setEditPriority(data.record.priority ?? "normal")
    setResearchPrompt(`${data.record.title}\n\n${data.record.content || ""}`.trim())
    setLoading(false)
  }, [recordId])

  useEffect(() => {
    setLoading(true)
    load()
  }, [load])

  // Poll research job status while one is active
  useEffect(() => {
    if (!latestResearch) return
    if (latestResearch.status === "queued" || latestResearch.status === "running") {
      pollRef.current = setInterval(async () => {
        const res = await fetch(`/api/operations/records/${recordId}/research`)
        if (res.ok) {
          const jobs: ResearchJob[] = await res.json()
          const current = jobs[0]
          if (current) {
            setLatestResearch(current)
            if (current.status === "completed" || current.status === "failed") {
              // Reload to pull in any new child records
              load()
              onChanged()
            }
          }
        }
      }, 3000)
      return () => { if (pollRef.current) clearInterval(pollRef.current) }
    }
  }, [latestResearch, recordId, load, onChanged])

  // ── Mutations ────────────────────────────────────────────────────────────

  async function patch(body: Partial<FullRecord>) {
    setSaving(true)
    const res = await fetch(`/api/operations/records/${recordId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    })
    setSaving(false)
    if (!res.ok) {
      setError("Save failed.")
      return null
    }
    const updated: FullRecord = await res.json()
    setRecord(updated)
    onChanged()
    return updated
  }

  async function saveEdits() {
    const updated = await patch({
      title: editTitle.trim() || "Untitled",
      content: editContent,
      type: editType,
      priority: editPriority,
    })
    if (updated) setEditing(false)
  }

  async function setStatus(s: RecordStatus) {
    await patch({ status: s })
  }

  async function togglePin() {
    if (!record) return
    await patch({ pinned: !record.pinned })
  }

  async function archive() {
    await patch({ archived_at: new Date().toISOString() })
    onClose()
  }

  async function destroy() {
    const childWarning = children.length > 0
      ? ` This will also permanently delete ${children.length} nested research record${children.length === 1 ? "" : "s"} under it.`
      : ""
    if (!confirm(`Delete this record permanently?${childWarning}`)) return
    const res = await fetch(`/api/operations/records/${recordId}`, { method: "DELETE" })
    if (res.ok) {
      onChanged()
      onClose()
    }
  }

  async function startResearch() {
    if (!researchPrompt.trim()) return
    setStartingResearch(true)
    const res = await fetch(`/api/operations/records/${recordId}/research`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ prompt: researchPrompt }),
    })
    setStartingResearch(false)
    if (!res.ok) {
      const err = await res.json().catch(() => ({}))
      setError(err.error || "Failed to start research.")
      return
    }
    const job: ResearchJob = await res.json()
    setLatestResearch(job)
    setResearchOpen(false)
  }

  function askEve() {
    if (!record) return
    const context = `I want to discuss this record from my operation:\n\nTitle: ${record.title}\n\n${record.content || "(no content)"}`
    // Stash in sessionStorage so we don't blow out the URL for long records
    try { sessionStorage.setItem("eve_prefill", context) } catch { /* noop */ }
    router.push("/dashboard/maxwell?prefill=1")
  }

  function toggleChild(id: string) {
    setExpandedChildren(prev => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id); else next.add(id)
      return next
    })
  }

  // ── Render ───────────────────────────────────────────────────────────────

  return (
    <>
      {/* Backdrop */}
      <button
        className="fixed inset-0 bg-foreground/30 backdrop-blur-sm z-40"
        onClick={onClose}
        aria-label="Close record"
      />

      {/* Drawer: full screen on mobile, right panel on desktop */}
      <aside
        className="fixed inset-0 md:inset-y-0 md:right-0 md:left-auto md:w-[min(720px,90vw)] bg-background border-l border-border z-50 flex flex-col overflow-hidden"
        role="dialog"
        aria-label="Record detail"
      >
        {loading || !record ? (
          <div className="flex-1 flex items-center justify-center">
            <Loader2 size={20} className="animate-spin text-muted-foreground" />
          </div>
        ) : (
          <>
            {/* ── Header bar ────────────────────────────────────────────── */}
            <div className="flex items-center justify-between gap-2 px-4 md:px-6 py-3 border-b border-border flex-shrink-0">
              <div className="flex items-center gap-2 min-w-0">
                <span className="text-[10px] font-mono text-muted-foreground uppercase tracking-widest">
                  {record.type}
                </span>
                <span className="text-[10px] text-muted-foreground">·</span>
                <span className="text-[10px] font-mono text-muted-foreground truncate">
                  via {record.source}
                </span>
                <span className="text-[10px] text-muted-foreground">·</span>
                <span className="text-[10px] font-mono text-muted-foreground flex items-center gap-1">
                  <Clock size={10} />
                  {timeAgo(record.created_at)}
                </span>
              </div>

              <div className="flex items-center gap-1 flex-shrink-0">
                <button
                  onClick={togglePin}
                  title={record.pinned ? "Unpin" : "Pin to top"}
                  className={`p-2 rounded-lg transition-colors ${record.pinned ? "text-yellow-400 bg-yellow-400/10" : "text-muted-foreground hover:text-foreground hover:bg-muted"}`}
                >
                  <Star size={15} fill={record.pinned ? "currentColor" : "none"} />
                </button>
                <button
                  onClick={archive}
                  title="Archive"
                  className="p-2 rounded-lg text-muted-foreground hover:text-foreground hover:bg-muted transition-colors"
                >
                  <Archive size={15} />
                </button>
                <button
                  onClick={destroy}
                  title="Delete permanently"
                  className="p-2 rounded-lg text-muted-foreground hover:text-destructive hover:bg-destructive/10 transition-colors"
                >
                  <Trash2 size={15} />
                </button>
                <button
                  onClick={onClose}
                  title="Close"
                  className="p-2 rounded-lg text-muted-foreground hover:text-foreground hover:bg-muted transition-colors"
                >
                  <X size={16} />
                </button>
              </div>
            </div>

            {/* ── Scrollable body ───────────────────────────────────────── */}
            <div className="flex-1 overflow-y-auto px-4 md:px-6 py-4 md:py-6">
              {/* Title + edit toggle */}
              <div className="flex items-start justify-between gap-3 mb-2">
                {editing ? (
                  <input
                    value={editTitle}
                    onChange={e => setEditTitle(e.target.value)}
                    className="flex-1 bg-background border border-border rounded-lg px-3 py-2 text-lg font-semibold text-foreground focus:outline-none focus:border-accent/50"
                    placeholder="Title"
                  />
                ) : (
                  <h2 className="text-xl md:text-2xl font-bold text-foreground leading-tight flex-1 min-w-0">
                    {record.title}
                  </h2>
                )}
                {!editing && (
                  <button
                    onClick={() => setEditing(true)}
                    title="Edit"
                    className="p-2 rounded-lg text-muted-foreground hover:text-foreground hover:bg-muted transition-colors flex-shrink-0"
                  >
                    <Pencil size={15} />
                  </button>
                )}
              </div>

              {/* Status + type + priority row */}
              <div className="flex flex-wrap items-center gap-2 mb-4">
                <StatusControl status={record.status} onChange={setStatus} disabled={saving} />

                {editing ? (
                  <>
                    <select
                      value={editType}
                      onChange={e => setEditType(e.target.value as RecordType)}
                      className="text-[11px] font-mono bg-background border border-border rounded px-2 py-1 text-foreground focus:outline-none focus:border-accent/50"
                    >
                      {TYPE_OPTIONS.map(t => <option key={t} value={t}>{t}</option>)}
                    </select>
                    <select
                      value={editPriority}
                      onChange={e => setEditPriority(e.target.value)}
                      className="text-[11px] font-mono bg-background border border-border rounded px-2 py-1 text-foreground focus:outline-none focus:border-accent/50"
                    >
                      {["low", "normal", "high", "critical"].map(p => <option key={p} value={p}>{p}</option>)}
                    </select>
                  </>
                ) : (
                  <>
                    <span className="text-[10px] font-mono text-muted-foreground uppercase tracking-widest border border-border px-2 py-0.5 rounded">
                      {record.type}
                    </span>
                    {record.priority !== "normal" && (
                      <span className="text-[10px] font-mono uppercase tracking-widest text-yellow-400 border border-yellow-400/40 bg-yellow-400/10 px-2 py-0.5 rounded">
                        {record.priority} priority
                      </span>
                    )}
                  </>
                )}
              </div>

              {/* Content: edit or markdown view */}
              {editing ? (
                <>
                  <textarea
                    value={editContent}
                    onChange={e => setEditContent(e.target.value)}
                    rows={12}
                    placeholder="Write freely — markdown is supported."
                    className="w-full bg-background border border-border rounded-lg px-3 py-3 text-sm text-foreground leading-relaxed focus:outline-none focus:border-accent/50 resize-y min-h-40 font-mono"
                  />
                  <div className="flex items-center justify-end gap-2 mt-3">
                    <button
                      onClick={() => { setEditing(false); setEditTitle(record.title); setEditContent(record.content) }}
                      className="text-xs border border-border text-muted-foreground px-4 py-1.5 rounded hover:bg-muted transition-colors"
                    >
                      Cancel
                    </button>
                    <button
                      onClick={saveEdits}
                      disabled={saving}
                      className="flex items-center gap-1.5 text-xs bg-accent text-accent-foreground font-medium px-4 py-1.5 rounded hover:opacity-90 transition-opacity disabled:opacity-60"
                    >
                      {saving ? <Loader2 size={12} className="animate-spin" /> : <Save size={12} />}
                      Save
                    </button>
                  </div>
                </>
              ) : (
                <div className="prose prose-sm dark:prose-invert max-w-none leading-relaxed
                  prose-headings:text-foreground prose-headings:font-semibold
                  prose-p:text-foreground prose-p:my-2
                  prose-strong:text-foreground
                  prose-a:text-accent prose-a:no-underline hover:prose-a:underline
                  prose-code:text-accent prose-code:bg-accent/10 prose-code:px-1 prose-code:py-0.5 prose-code:rounded prose-code:text-xs prose-code:before:content-none prose-code:after:content-none
                  prose-pre:bg-muted prose-pre:border prose-pre:border-border prose-pre:rounded-lg
                  prose-li:text-foreground prose-li:marker:text-accent
                  prose-blockquote:border-l-accent prose-blockquote:text-foreground/80
                  prose-hr:border-border
                ">
                  {record.content
                    ? <ReactMarkdown remarkPlugins={[remarkGfm]}>{record.content}</ReactMarkdown>
                    : <p className="text-muted-foreground italic">No content yet. Click the pencil to add some.</p>
                  }
                </div>
              )}

              {/* ── Actions: Ask Eve / Research ──────────────────────── */}
              {!editing && (
                <div className="mt-6 pt-5 border-t border-border flex flex-wrap items-center gap-2">
                  <button
                    onClick={askEve}
                    className="flex items-center gap-2 text-xs font-semibold bg-accent text-accent-foreground px-3 py-2 rounded-lg hover:opacity-90 transition-opacity"
                  >
                    <MessageSquare size={13} />
                    Ask Eve about this
                  </button>
                  <button
                    onClick={() => setResearchOpen(v => !v)}
                    disabled={latestResearch?.status === "queued" || latestResearch?.status === "running"}
                    className="flex items-center gap-2 text-xs font-semibold border border-border text-foreground hover:border-accent/40 hover:bg-accent/5 px-3 py-2 rounded-lg transition-colors disabled:opacity-60"
                  >
                    <FlaskConical size={13} />
                    {latestResearch?.status === "running" ? "Researching…" : latestResearch?.status === "queued" ? "Queued…" : "Task Eve to research"}
                  </button>
                </div>
              )}

              {/* ── Research prompt editor ──────────────────────────── */}
              {researchOpen && (
                <div className="mt-3 border border-border rounded-lg bg-card p-4">
                  <p className="text-[11px] font-mono text-muted-foreground uppercase tracking-widest mb-2">
                    Research Brief
                  </p>
                  <p className="text-xs text-muted-foreground mb-3">
                    Refine the brief below. Eve will run in the background and produce a dossier of findings nested under this record.
                  </p>
                  <textarea
                    value={researchPrompt}
                    onChange={e => setResearchPrompt(e.target.value)}
                    rows={4}
                    className="w-full bg-background border border-border rounded-lg px-3 py-2 text-sm text-foreground focus:outline-none focus:border-accent/50 resize-y min-h-24"
                    placeholder="What should Eve research?"
                  />
                  <div className="flex items-center justify-end gap-2 mt-2">
                    <button
                      onClick={() => setResearchOpen(false)}
                      className="text-xs border border-border text-muted-foreground px-3 py-1.5 rounded hover:bg-muted transition-colors"
                    >
                      Cancel
                    </button>
                    <button
                      onClick={startResearch}
                      disabled={startingResearch || !researchPrompt.trim()}
                      className="flex items-center gap-1.5 text-xs bg-accent text-accent-foreground font-medium px-4 py-1.5 rounded hover:opacity-90 transition-opacity disabled:opacity-50"
                    >
                      {startingResearch ? <Loader2 size={12} className="animate-spin" /> : <FlaskConical size={12} />}
                      Launch Research
                    </button>
                  </div>
                </div>
              )}

              {/* ── Job status banner ───────────────────────────────── */}
              {latestResearch && (latestResearch.status === "running" || latestResearch.status === "queued") && (
                <div className="mt-3 flex items-center gap-2 border border-accent/30 bg-accent/5 rounded-lg px-4 py-3">
                  <Loader2 size={14} className="animate-spin text-accent" />
                  <p className="text-xs text-foreground">
                    {latestResearch.progress_note || "Eve is working on the research dossier…"}
                  </p>
                </div>
              )}
              {latestResearch && latestResearch.status === "failed" && (
                <div className="mt-3 flex items-start gap-2 border border-destructive/40 bg-destructive/5 rounded-lg px-4 py-3">
                  <AlertTriangle size={14} className="text-destructive flex-shrink-0 mt-0.5" />
                  <div className="min-w-0">
                    <p className="text-xs font-semibold text-destructive">Research failed</p>
                    <p className="text-xs text-muted-foreground mt-0.5">{latestResearch.error}</p>
                  </div>
                </div>
              )}

              {/* ── Nested research / children ──────────────────────── */}
              {children.length > 0 && (
                <div className="mt-6 pt-5 border-t border-border">
                  <p className="text-[10px] font-mono text-muted-foreground uppercase tracking-widest mb-3">
                    Research & Nested Findings ({children.length})
                  </p>
                  <div className="space-y-2">
                    {children.map(child => {
                      const expanded = expandedChildren.has(child.id)
                      return (
                        <div key={child.id} className="border border-border rounded-lg overflow-hidden">
                          <button
                            onClick={() => toggleChild(child.id)}
                            className="w-full flex items-center gap-2 px-3 py-2.5 text-left hover:bg-muted/50 transition-colors"
                          >
                            {expanded ? <ChevronDown size={14} className="text-muted-foreground flex-shrink-0" /> : <ChevronRight size={14} className="text-muted-foreground flex-shrink-0" />}
                            <span className="text-[10px] font-mono text-muted-foreground uppercase">{child.type}</span>
                            <span className="text-sm font-medium text-foreground truncate flex-1">{child.title}</span>
                            <span className="text-[10px] text-muted-foreground flex-shrink-0">{timeAgo(child.created_at)}</span>
                          </button>
                          {expanded && (
                            <div className="px-4 pb-4 pt-1 prose prose-sm dark:prose-invert max-w-none leading-relaxed
                              prose-headings:text-foreground prose-p:text-foreground prose-p:my-1.5
                              prose-a:text-accent prose-a:no-underline hover:prose-a:underline
                              prose-li:text-foreground prose-li:marker:text-accent
                            ">
                              <ReactMarkdown remarkPlugins={[remarkGfm]}>{child.content}</ReactMarkdown>
                            </div>
                          )}
                        </div>
                      )
                    })}
                  </div>
                </div>
              )}

              {error && (
                <div className="mt-4 text-xs text-destructive">{error}</div>
              )}
            </div>
          </>
        )}
      </aside>
    </>
  )
}

// ── Status control ──────────────────────────────────────────────────────────

function StatusControl({
  status, onChange, disabled,
}: {
  status: RecordStatus
  onChange: (s: RecordStatus) => void
  disabled: boolean
}) {
  const [open, setOpen] = useState(false)
  const CurrentIcon = status ? STATUS_META[status].icon : Circle
  const currentClass = status ? STATUS_META[status].className : "text-muted-foreground border-border border-dashed"
  const currentLabel = status ? STATUS_META[status].label : "No status"

  return (
    <div className="relative">
      <button
        onClick={() => setOpen(v => !v)}
        disabled={disabled}
        className={`flex items-center gap-1.5 text-[11px] font-medium border px-2 py-1 rounded transition-colors ${currentClass}`}
      >
        <CurrentIcon size={12} />
        {currentLabel}
      </button>
      {open && (
        <>
          <button
            className="fixed inset-0 z-10"
            onClick={() => setOpen(false)}
            aria-hidden
          />
          <div className="absolute top-full left-0 mt-1 min-w-[140px] bg-card border border-border rounded-lg shadow-lg z-20 py-1">
            {STATUS_ORDER.map(s => {
              const meta = STATUS_META[s]
              const Icon = meta.icon
              return (
                <button
                  key={s}
                  onClick={() => { onChange(s); setOpen(false) }}
                  className="w-full flex items-center gap-2 px-3 py-1.5 text-xs text-foreground hover:bg-muted transition-colors text-left"
                >
                  <Icon size={12} className={meta.className.split(" ")[0]} />
                  {meta.label}
                  {status === s && <Check size={12} className="ml-auto text-accent" />}
                </button>
              )
            })}
            {status !== null && (
              <>
                <div className="h-px bg-border my-1" />
                <button
                  onClick={() => { onChange(null); setOpen(false) }}
                  className="w-full flex items-center gap-2 px-3 py-1.5 text-xs text-muted-foreground hover:bg-muted transition-colors text-left"
                >
                  Clear status
                </button>
              </>
            )}
          </div>
        </>
      )}
    </div>
  )
}
