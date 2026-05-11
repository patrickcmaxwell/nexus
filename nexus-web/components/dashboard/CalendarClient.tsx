"use client"

// Calendar (schedules) management UI.
//
// Design baseline: Apple/Linear-style. No HUD chrome (no all-caps mono
// labels, no neon-glow borders, no cyan-on-near-black). Sentence-case
// typography, soft cards, generous spacing, single accent.

import { useState, useTransition, useMemo } from "react"
import { useRouter } from "next/navigation"
import {
  Plus, Trash2, Power, Pencil, CheckCircle2, AlertTriangle,
  CalendarClock, Clock, Loader2, X, Play, ChevronDown, ChevronRight, History,
} from "lucide-react"

type Target = "eve_chat" | "agent_run" | "operation_brief" | "arena_action"

type Schedule = {
  id: string
  name: string
  description: string | null
  cron_expression: string
  timezone: string
  target_type: Target
  target_id: string | null
  payload: Record<string, unknown> | null
  enabled: boolean
  next_run_at: string | null
  last_run_at: string | null
  last_status: string | null
  last_error: string | null
  created_at: string
}

type RefList = Array<{ id: string; name?: string; title?: string }>

const TARGET_LABEL: Record<Target, string> = {
  eve_chat:        "Post to Eve chat",
  agent_run:       "Run an agent",
  operation_brief: "Generate operation brief",
  arena_action:    "Fire Arena action",
}

const COMMON_CRONS: Array<{ label: string; expr: string }> = [
  { label: "Every minute (test)",  expr: "* * * * *" },
  { label: "Every 15 minutes",     expr: "*/15 * * * *" },
  { label: "Hourly",               expr: "0 * * * *" },
  { label: "Daily at 9 AM",        expr: "0 9 * * *" },
  { label: "Daily at 5 PM",        expr: "0 17 * * *" },
  { label: "Weekdays at 9 AM",     expr: "0 9 * * 1-5" },
  { label: "Mondays at 9 AM",      expr: "0 9 * * 1" },
  { label: "First of every month", expr: "0 0 1 * *" },
]

export default function CalendarClient({
  initialSchedules, conversations, agents, operations,
}: {
  initialSchedules: Schedule[]
  conversations: RefList
  agents: RefList
  operations: RefList
}) {
  const router = useRouter()
  const [schedules, setSchedules] = useState<Schedule[]>(initialSchedules)
  const [editing, setEditing] = useState<Schedule | null>(null)
  const [creating, setCreating] = useState(false)
  const [_pending, startTransition] = useTransition()

  async function refresh() {
    const res = await fetch("/api/schedules", { cache: "no-store" })
    if (res.ok) {
      const { schedules: next } = await res.json()
      setSchedules(next)
    }
    startTransition(() => router.refresh())
  }

  async function toggleEnabled(s: Schedule) {
    const res = await fetch(`/api/schedules/${s.id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ enabled: !s.enabled }),
    })
    if (res.ok) await refresh()
  }

  async function remove(s: Schedule) {
    if (!confirm(`Delete schedule "${s.name}"? Past runs in the audit log are kept.`)) return
    const res = await fetch(`/api/schedules/${s.id}`, { method: "DELETE" })
    if (res.ok) {
      setSchedules(prev => prev.filter(x => x.id !== s.id))
    }
  }

  async function runNow(s: Schedule): Promise<{ ok: boolean; detail?: string }> {
    const res = await fetch(`/api/schedules/${s.id}/run`, { method: "POST" })
    const data = await res.json().catch(() => ({} as Record<string, unknown>))
    if (res.ok && data.success) {
      await refresh()
      return { ok: true }
    }
    return { ok: false, detail: (data.error as string | undefined) || `HTTP ${res.status}` }
  }

  return (
    <div className="min-h-screen px-4 sm:px-6 md:px-10 py-10 max-w-5xl mx-auto">
      <header className="mb-10 flex items-start justify-between gap-3">
        <div className="min-w-0">
          <h1 className="text-2xl font-semibold tracking-tight text-foreground">Calendar</h1>
          <p className="text-sm text-muted-foreground mt-2 max-w-lg leading-relaxed">
            Recurring rules that fire actions on their own — post to Eve, run an agent, generate a brief, or call an Arena tool.
          </p>
        </div>
        <button
          onClick={() => setCreating(true)}
          className="flex items-center gap-2 px-4 py-2 rounded-lg bg-primary text-primary-foreground hover:opacity-90 transition-opacity flex-shrink-0 text-sm font-medium"
        >
          <Plus size={15} />
          New schedule
        </button>
      </header>

      {schedules.length === 0 ? (
        <EmptyState onCreate={() => setCreating(true)} />
      ) : (
        <ul className="flex flex-col gap-3">
          {schedules.map(s => (
            <ScheduleRow
              key={s.id}
              schedule={s}
              onToggle={() => toggleEnabled(s)}
              onEdit={() => setEditing(s)}
              onDelete={() => remove(s)}
              onRun={() => runNow(s)}
            />
          ))}
        </ul>
      )}

      <p className="text-xs text-muted-foreground mt-8 text-center">
        Tip — you can also tell Eve: <span className="text-foreground/80">&ldquo;remind me daily at 9am to check Londynn.&rdquo;</span>
      </p>

      {(creating || editing) && (
        <ScheduleModal
          existing={editing}
          conversations={conversations}
          agents={agents}
          operations={operations}
          onClose={() => { setCreating(false); setEditing(null) }}
          onSaved={async () => { setCreating(false); setEditing(null); await refresh() }}
        />
      )}
    </div>
  )
}

type ScheduleRunRow = {
  id: string
  fired_at: string
  status: string
  result: Record<string, unknown> | null
  error_msg: string | null
  duration_ms: number | null
}

function ScheduleRow({
  schedule, onToggle, onEdit, onDelete, onRun,
}: {
  schedule: Schedule
  onToggle: () => void
  onEdit: () => void
  onDelete: () => void
  onRun: () => Promise<{ ok: boolean; detail?: string }>
}) {
  const s = schedule
  const [running, setRunning] = useState(false)
  const [runFlash, setRunFlash] = useState<{ ok: boolean; detail?: string } | null>(null)
  const [expanded, setExpanded] = useState(false)
  const [history, setHistory] = useState<ScheduleRunRow[] | null>(null)

  async function handleRun() {
    setRunning(true)
    setRunFlash(null)
    const r = await onRun()
    setRunFlash(r)
    setRunning(false)
    setTimeout(() => setRunFlash(null), 4000)
    if (expanded) await loadHistory()
  }

  async function loadHistory() {
    const res = await fetch(`/api/schedules/${s.id}`)
    if (res.ok) {
      const data = await res.json()
      setHistory(data.runs ?? [])
    }
  }

  async function toggleExpanded() {
    const next = !expanded
    setExpanded(next)
    if (next && history === null) await loadHistory()
  }

  return (
    <li className="rounded-xl bg-card border border-border hover:border-border/80 transition-colors">
      <div className="px-4 py-4 flex flex-col sm:flex-row sm:items-center gap-3">
        <button
          onClick={toggleExpanded}
          className="text-muted-foreground hover:text-foreground self-start mt-0.5 sm:mt-0 flex-shrink-0 transition-colors"
          aria-label={expanded ? "Collapse" : "Expand history"}
        >
          {expanded ? <ChevronDown size={16} /> : <ChevronRight size={16} />}
        </button>
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2 flex-wrap">
            <p className={`text-base font-medium ${s.enabled ? "text-foreground" : "text-muted-foreground"}`}>
              {s.name}
            </p>
            {!s.enabled && (
              <span className="text-xs text-muted-foreground bg-muted px-2 py-0.5 rounded">Paused</span>
            )}
            {s.last_status === "success" && (
              <span className="text-xs text-nexus-success/90 bg-nexus-success/10 px-2 py-0.5 rounded flex items-center gap-1">
                <CheckCircle2 size={11} /> Last run ok
              </span>
            )}
            {s.last_status === "error" && (
              <span className="text-xs text-nexus-danger bg-nexus-danger/10 px-2 py-0.5 rounded flex items-center gap-1">
                <AlertTriangle size={11} /> Last run failed
              </span>
            )}
          </div>
          <div className="flex items-center gap-2 mt-1 text-xs text-muted-foreground flex-wrap">
            <span>{TARGET_LABEL[s.target_type]}</span>
            <span className="text-foreground/20">·</span>
            <span className="font-mono text-foreground/70">{s.cron_expression}</span>
            <span className="text-foreground/20">·</span>
            <span className="flex items-center gap-1">
              <CalendarClock size={11} />
              {s.next_run_at ? `Next ${formatTime(s.next_run_at)}` : "—"}
            </span>
            {s.last_run_at && (
              <>
                <span className="text-foreground/20">·</span>
                <span>Last {timeAgo(s.last_run_at)}</span>
              </>
            )}
          </div>
          {s.last_error && (
            <p className="text-xs text-nexus-danger mt-1.5 font-mono truncate">{s.last_error}</p>
          )}
          {runFlash && (
            <p className={`text-xs mt-1.5 ${runFlash.ok ? "text-nexus-success" : "text-nexus-danger"}`}>
              {runFlash.ok ? "✓ Fired" : `Failed: ${runFlash.detail}`}
            </p>
          )}
        </div>
        <div className="flex items-center gap-1 self-end sm:self-auto flex-shrink-0">
          <IconButton onClick={handleRun} disabled={running} title="Run now (skip the cron tick)" tone="accent">
            {running ? <Loader2 size={15} className="animate-spin" /> : <Play size={15} />}
          </IconButton>
          <IconButton onClick={onToggle} title={s.enabled ? "Pause" : "Resume"} tone={s.enabled ? "muted" : "accent"}>
            <Power size={15} />
          </IconButton>
          <IconButton onClick={onEdit} title="Edit" tone="muted">
            <Pencil size={15} />
          </IconButton>
          <IconButton onClick={onDelete} title="Delete" tone="danger">
            <Trash2 size={15} />
          </IconButton>
        </div>
      </div>

      {expanded && (
        <div className="border-t border-border px-4 py-3 bg-background/30">
          <div className="flex items-center gap-2 mb-2 text-xs text-muted-foreground">
            <History size={12} />
            <span>Recent runs ({history?.length ?? 0})</span>
          </div>
          {history === null ? (
            <p className="text-xs text-muted-foreground">Loading…</p>
          ) : history.length === 0 ? (
            <p className="text-xs text-muted-foreground">No runs yet — hit the play button to fire one now.</p>
          ) : (
            <ul className="flex flex-col gap-1">
              {history.slice(0, 8).map(run => (
                <li key={run.id} className="flex items-center gap-3 text-xs py-1">
                  <span className={`font-medium ${
                    run.status === "success" ? "text-nexus-success" : run.status === "error" ? "text-nexus-danger" : "text-muted-foreground"
                  }`}>
                    {run.status === "success" ? "✓" : run.status === "error" ? "✗" : "·"}
                  </span>
                  <span className="text-muted-foreground">{formatTime(run.fired_at)}</span>
                  {typeof run.duration_ms === "number" && (
                    <span className="text-muted-foreground/60">{run.duration_ms}ms</span>
                  )}
                  {run.error_msg && (
                    <span className="text-nexus-danger truncate flex-1">{run.error_msg}</span>
                  )}
                  {(run.result as { manual?: boolean } | null)?.manual && (
                    <span className="text-muted-foreground/70 ml-auto">manual</span>
                  )}
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
    </li>
  )
}

function IconButton({
  onClick, disabled, title, tone, children,
}: {
  onClick: () => void; disabled?: boolean; title: string; tone: "accent" | "muted" | "danger"; children: React.ReactNode
}) {
  const toneClasses = {
    accent: "text-muted-foreground hover:text-primary hover:bg-primary/10",
    muted:  "text-muted-foreground hover:text-foreground hover:bg-muted",
    danger: "text-muted-foreground hover:text-nexus-danger hover:bg-nexus-danger/10",
  }[tone]
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      title={title}
      className={`p-2 rounded-lg transition-colors disabled:opacity-40 ${toneClasses}`}
    >
      {children}
    </button>
  )
}

function EmptyState({ onCreate }: { onCreate: () => void }) {
  return (
    <div className="rounded-xl border border-border bg-card p-12 text-center">
      <CalendarClock size={32} className="mx-auto mb-4 text-muted-foreground/40" />
      <p className="text-base font-medium text-foreground mb-2">No schedules yet</p>
      <p className="text-sm text-muted-foreground max-w-md mx-auto leading-relaxed mb-6">
        Create one to have Eve, an agent, an operation, or an Arena tool fire on a recurring time. Or just ask Eve in chat: &ldquo;remind me daily at 9am to check Londynn.&rdquo;
      </p>
      <button
        onClick={onCreate}
        className="inline-flex items-center gap-2 px-5 py-2.5 rounded-lg bg-primary text-primary-foreground hover:opacity-90 transition-opacity text-sm font-medium"
      >
        <Plus size={15} />
        Create your first schedule
      </button>
    </div>
  )
}

function ScheduleModal({
  existing, conversations, agents, operations, onClose, onSaved,
}: {
  existing: Schedule | null
  conversations: RefList
  agents: RefList
  operations: RefList
  onClose: () => void
  onSaved: () => void | Promise<void>
}) {
  const isEdit = !!existing
  const [name, setName]               = useState(existing?.name ?? "")
  const [cron, setCron]               = useState(existing?.cron_expression ?? "0 9 * * *")
  const [tz, setTz]                   = useState(existing?.timezone ?? "America/Chicago")
  const [targetType, setTargetType]   = useState<Target>(existing?.target_type ?? "eve_chat")
  const [targetId, setTargetId]       = useState(existing?.target_id ?? "")
  const [message, setMessage]         = useState(((existing?.payload as { message?: string } | null)?.message) ?? "")
  const [briefKind, setBriefKind]     = useState(((existing?.payload as { kind?: string } | null)?.kind) ?? "summary")
  const [arenaEndpoint, setArenaEndpoint] = useState(((existing?.payload as { endpoint?: string } | null)?.endpoint) ?? "")
  const [arenaBody, setArenaBody]     = useState(JSON.stringify(((existing?.payload as { body?: object } | null)?.body) ?? {}, null, 2))
  const [submitting, setSubmitting]   = useState(false)
  const [error, setError]             = useState<string | null>(null)

  const previewFirings = useMemo<{ ok: true; firings: string[] } | { ok: false; reason: string }>(() => {
    if (!cron.trim()) return { ok: true, firings: [] }
    try {
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      const { CronExpressionParser } = require("cron-parser") as typeof import("cron-parser")
      const interval = CronExpressionParser.parse(cron.trim(), { tz })
      const out: string[] = []
      for (let i = 0; i < 3; i++) out.push(interval.next().toDate().toISOString())
      return { ok: true, firings: out }
    } catch (err) {
      return { ok: false, reason: err instanceof Error ? err.message : "invalid" }
    }
  }, [cron, tz])

  function buildPayload(): Record<string, unknown> {
    if (targetType === "eve_chat")        return { message }
    if (targetType === "operation_brief") return { kind: briefKind }
    if (targetType === "arena_action") {
      let body: Record<string, unknown> = {}
      try { body = JSON.parse(arenaBody || "{}") } catch { body = {} }
      return { endpoint: arenaEndpoint, body }
    }
    return {}
  }

  async function save() {
    setSubmitting(true)
    setError(null)
    const url = isEdit ? `/api/schedules/${existing!.id}` : "/api/schedules"
    const method = isEdit ? "PATCH" : "POST"
    try {
      const res = await fetch(url, {
        method,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: name.trim(),
          cron_expression: cron.trim(),
          timezone: tz,
          target_type: targetType,
          target_id: targetType === "arena_action" ? null : (targetId || null),
          payload: buildPayload(),
        }),
      })
      const data = await res.json().catch(() => ({}))
      if (!res.ok) {
        setError(data.error || `HTTP ${res.status}`)
        return
      }
      await onSaved()
    } catch (err) {
      setError(err instanceof Error ? err.message : "Network error")
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-background/85 backdrop-blur-sm z-50 flex items-end sm:items-center justify-center p-0 sm:p-4">
      <div className="bg-card border-t sm:border border-border w-full sm:rounded-2xl sm:max-w-xl max-h-[92vh] overflow-y-auto p-5 sm:p-7 flex flex-col gap-5">
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-semibold tracking-tight text-foreground">
            {isEdit ? "Edit schedule" : "New schedule"}
          </h2>
          <button onClick={onClose} className="p-1.5 text-muted-foreground hover:text-foreground hover:bg-muted rounded-lg transition-colors">
            <X size={16} />
          </button>
        </div>

        <Field label="Name">
          <input
            type="text"
            value={name}
            onChange={e => setName(e.target.value)}
            placeholder="e.g. Daily Londynn check-in"
            className="w-full bg-background border border-border focus:border-primary focus:outline-none text-sm text-foreground px-3 py-2.5 rounded-lg transition-colors"
            maxLength={200}
            autoFocus
          />
        </Field>

        <Field label="When" helper="Pick a preset or write a cron expression.">
          <div className="flex flex-wrap gap-1.5 mb-2">
            {COMMON_CRONS.map(c => (
              <button
                key={c.expr}
                type="button"
                onClick={() => setCron(c.expr)}
                className={`text-xs px-2.5 py-1.5 rounded-md transition-colors ${
                  cron === c.expr
                    ? "bg-primary/15 text-primary"
                    : "bg-muted text-muted-foreground hover:text-foreground"
                }`}
              >
                {c.label}
              </button>
            ))}
          </div>
          <input
            type="text"
            value={cron}
            onChange={e => setCron(e.target.value)}
            placeholder="0 9 * * *"
            className="w-full bg-background border border-border focus:border-primary focus:outline-none text-sm font-mono text-foreground px-3 py-2.5 rounded-lg transition-colors"
          />
          <div className="mt-2 px-3 py-2 rounded-lg bg-muted/40 text-xs">
            {previewFirings.ok ? (
              previewFirings.firings.length === 0 ? (
                <span className="text-muted-foreground">Enter a cron to see next firings</span>
              ) : (
                <div className="flex flex-col gap-0.5">
                  <span className="text-muted-foreground mb-1">Next firings</span>
                  {previewFirings.firings.map((iso, i) => (
                    <span key={i} className="text-foreground/80">
                      {new Date(iso).toLocaleString("en-US", { weekday: "short", month: "short", day: "numeric", hour: "numeric", minute: "2-digit", timeZone: tz })}
                    </span>
                  ))}
                </div>
              )
            ) : (
              <span className="text-nexus-danger">{previewFirings.reason}</span>
            )}
          </div>
        </Field>

        <Field label="Timezone" helper="IANA tz database name.">
          <input
            type="text"
            value={tz}
            onChange={e => setTz(e.target.value)}
            placeholder="America/Chicago"
            className="w-full bg-background border border-border focus:border-primary focus:outline-none text-sm font-mono text-foreground px-3 py-2.5 rounded-lg transition-colors"
          />
        </Field>

        <Field label="What fires">
          <select
            value={targetType}
            onChange={e => { setTargetType(e.target.value as Target); setTargetId("") }}
            className="w-full bg-background border border-border focus:border-primary focus:outline-none text-sm text-foreground px-3 py-2.5 rounded-lg transition-colors"
          >
            {Object.entries(TARGET_LABEL).map(([v, label]) => (
              <option key={v} value={v}>{label}</option>
            ))}
          </select>
        </Field>

        {targetType === "eve_chat" && (
          <>
            <Field label="Conversation">
              <select
                value={targetId}
                onChange={e => setTargetId(e.target.value)}
                className="w-full bg-background border border-border focus:border-primary focus:outline-none text-sm text-foreground px-3 py-2.5 rounded-lg transition-colors"
              >
                <option value="">— pick a conversation —</option>
                {conversations.map(c => (
                  <option key={c.id} value={c.id}>{c.title || c.id.slice(0, 8)}</option>
                ))}
              </select>
            </Field>
            <Field label="Message to post">
              <textarea
                value={message}
                onChange={e => setMessage(e.target.value)}
                rows={3}
                placeholder="Quick check on Londynn — what's outstanding?"
                className="w-full bg-background border border-border focus:border-primary focus:outline-none text-sm text-foreground px-3 py-2.5 rounded-lg transition-colors resize-none"
              />
            </Field>
          </>
        )}

        {targetType === "agent_run" && (
          <Field label="Agent">
            <select
              value={targetId}
              onChange={e => setTargetId(e.target.value)}
              className="w-full bg-background border border-border focus:border-primary focus:outline-none text-sm text-foreground px-3 py-2.5 rounded-lg transition-colors"
            >
              <option value="">— pick an agent —</option>
              {agents.map(a => <option key={a.id} value={a.id}>{a.name}</option>)}
            </select>
          </Field>
        )}

        {targetType === "operation_brief" && (
          <>
            <Field label="Operation">
              <select
                value={targetId}
                onChange={e => setTargetId(e.target.value)}
                className="w-full bg-background border border-border focus:border-primary focus:outline-none text-sm text-foreground px-3 py-2.5 rounded-lg transition-colors"
              >
                <option value="">— pick an operation —</option>
                {operations.map(o => <option key={o.id} value={o.id}>{o.name}</option>)}
              </select>
            </Field>
            <Field label="Brief kind">
              <select
                value={briefKind}
                onChange={e => setBriefKind(e.target.value)}
                className="w-full bg-background border border-border focus:border-primary focus:outline-none text-sm text-foreground px-3 py-2.5 rounded-lg transition-colors"
              >
                <option value="summary">Summary</option>
                <option value="actions">Actions</option>
                <option value="contradictions">Contradictions</option>
                <option value="themes">Themes</option>
                <option value="next-steps">Next steps</option>
              </select>
            </Field>
          </>
        )}

        {targetType === "arena_action" && (
          <>
            <Field label="Arena endpoint" helper="Path under arena.maxnexus.io, e.g. api/task/create">
              <input
                type="text"
                value={arenaEndpoint}
                onChange={e => setArenaEndpoint(e.target.value)}
                placeholder="api/task/create"
                className="w-full bg-background border border-border focus:border-primary focus:outline-none text-sm font-mono text-foreground px-3 py-2.5 rounded-lg transition-colors"
              />
            </Field>
            <Field label="Body (JSON)">
              <textarea
                value={arenaBody}
                onChange={e => setArenaBody(e.target.value)}
                rows={4}
                placeholder='{"provider":"clickup","title":"Daily review"}'
                className="w-full bg-background border border-border focus:border-primary focus:outline-none text-sm font-mono text-foreground px-3 py-2.5 rounded-lg transition-colors resize-none"
              />
            </Field>
          </>
        )}

        {error && (
          <div className="px-3 py-2 bg-nexus-danger/10 border border-nexus-danger/30 rounded-lg flex items-center gap-2">
            <AlertTriangle size={14} className="text-nexus-danger flex-shrink-0" />
            <p className="text-sm text-nexus-danger">{error}</p>
          </div>
        )}

        <div className="flex items-center justify-end gap-2 pt-2">
          <button
            onClick={onClose}
            className="px-4 py-2 text-sm text-muted-foreground hover:text-foreground rounded-lg hover:bg-muted transition-colors"
          >
            Cancel
          </button>
          <button
            onClick={save}
            disabled={submitting || !name.trim() || !cron.trim()}
            className="px-5 py-2 rounded-lg bg-primary text-primary-foreground text-sm font-medium flex items-center gap-2 disabled:opacity-40 hover:opacity-90 transition-opacity"
          >
            {submitting ? <Loader2 size={14} className="animate-spin" /> : null}
            {isEdit ? "Save changes" : "Create schedule"}
          </button>
        </div>
      </div>
    </div>
  )
}

function Field({ label, helper, children }: { label: string; helper?: string; children: React.ReactNode }) {
  return (
    <label className="flex flex-col gap-1.5">
      <span className="text-sm font-medium text-foreground">{label}</span>
      {children}
      {helper && <span className="text-xs text-muted-foreground">{helper}</span>}
    </label>
  )
}

function formatTime(iso: string): string {
  const d = new Date(iso)
  return d.toLocaleString("en-US", { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" })
}

function timeAgo(iso: string): string {
  const ms = Date.now() - new Date(iso).getTime()
  const m = Math.round(ms / 60000)
  if (m < 1)  return "just now"
  if (m < 60) return `${m}m ago`
  const h = Math.round(m / 60)
  if (h < 24) return `${h}h ago`
  const d = Math.round(h / 24)
  return `${d}d ago`
}
