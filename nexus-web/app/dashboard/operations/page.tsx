"use client"

import { useState, useEffect, useCallback } from "react"
import Link from "next/link"
import {
  Plus, ChevronRight, Circle,
  Trash2, UserPlus, X, Shield, Clock,
} from "lucide-react"
import RecordsList, { type ListRecord } from "@/components/dashboard/operations/RecordsList"
import RecordDetail from "@/components/dashboard/operations/RecordDetail"
import OperationBriefs from "@/components/dashboard/operations/OperationBriefs"

// ── Types ─────────────────────────────────────────────────────────────────────

type OpStatus   = "planning" | "active" | "paused" | "complete" | "aborted"
type OpPriority = "low" | "medium" | "high" | "critical"
type RecordType = "note" | "intel" | "data" | "finding" | "alert" | "file"

interface Agent {
  id: string
  name: string
  role: string
  status: string
}

interface AssignedAgent {
  role_in_op: string | null
  agents: Agent
}

type OperationRecord = ListRecord

interface Operation {
  id: string
  name: string
  codename: string | null
  description: string
  objectives: string
  status: OpStatus
  priority: OpPriority
  directives: string
  tags: string[]
  created_at: string
  updated_at: string
  operation_records: [{ count: number }]
  operation_agents: AssignedAgent[]
}

// ── Helpers ───────────────────────────────────────────────────────────────────

const STATUS_STYLES: Record<OpStatus, string> = {
  planning: "text-muted-foreground border-border",
  active:   "text-accent border-accent/50 bg-accent/5",
  paused:   "text-yellow-400 border-yellow-400/40 bg-yellow-400/5",
  complete: "text-green-400 border-green-400/40 bg-green-400/5",
  aborted:  "text-destructive border-destructive/40 bg-destructive/5",
}

const PRIORITY_STYLES: Record<OpPriority, string> = {
  low:      "text-muted-foreground",
  medium:   "text-foreground",
  high:     "text-yellow-400",
  critical: "text-destructive",
}

const STATUS_CYCLE: OpStatus[] = ["planning", "active", "paused", "complete", "aborted"]

function timeAgo(date: string) {
  const diff = Date.now() - new Date(date).getTime()
  const m = Math.floor(diff / 60000)
  if (m < 1) return "just now"
  if (m < 60) return `${m}m ago`
  const h = Math.floor(m / 60)
  if (h < 24) return `${h}h ago`
  return `${Math.floor(h / 24)}d ago`
}

// ── Main Page ─────────────────────────────────────────────────────────────────

export default function OperationsPage() {
  const [operations, setOperations] = useState<Operation[]>([])
  const [allAgents, setAllAgents]   = useState<Agent[]>([])
  const [selected, setSelected]     = useState<Operation | null>(null)
  const [records, setRecords]       = useState<OperationRecord[]>([])
  const [loading, setLoading]       = useState(true)
  const [showNewOp, setShowNewOp]   = useState(false)
  const [showNewRec, setShowNewRec] = useState(false)
  const [showAssign, setShowAssign] = useState(false)
  const [openRecordId, setOpenRecordId] = useState<string | null>(null)

  // New operation form
  const [newName, setNewName]             = useState("")
  const [newCodename, setNewCodename]     = useState("")
  const [newDesc, setNewDesc]             = useState("")
  const [newObjectives, setNewObjectives] = useState("")
  const [newDirectives, setNewDirectives] = useState("")
  const [newPriority, setNewPriority]     = useState<OpPriority>("medium")
  const [newVisibility, setNewVisibility] = useState<"private" | "shared" | "group" | "public">("private")

  // New record form
  const [recTitle, setRecTitle]       = useState("")
  const [recContent, setRecContent]   = useState("")
  const [recType, setRecType]         = useState<RecordType>("note")
  const [recSource, setRecSource]     = useState("manual")
  const [recPriority, setRecPriority] = useState("normal")

  const loadOperations = useCallback(async () => {
    setLoading(true)
    const res = await fetch("/api/operations")
    if (res.ok) {
      const data = await res.json()
      setOperations(Array.isArray(data) ? data : (data.operations ?? []))
    }
    setLoading(false)
  }, [])

  const loadAgents = useCallback(async () => {
    const res = await fetch("/api/agents")
    if (res.ok) setAllAgents(await res.json())
  }, [])

  const loadRecords = useCallback(async (opId: string) => {
    const res = await fetch(`/api/operations/records?operation_id=${opId}`)
    if (res.ok) setRecords(await res.json())
  }, [])

  useEffect(() => { loadOperations(); loadAgents() }, [loadOperations, loadAgents])

  // On mount, nudge the research watchdog — this picks up any jobs that
  // got stranded mid-deploy or during a preview cold-start and either
  // resumes them or marks them failed so nothing gets silently lost.
  useEffect(() => {
    fetch("/api/operations/research/watchdog", { method: "POST" }).catch(() => { /* noop */ })
  }, [])
  useEffect(() => { if (selected) loadRecords(selected.id) }, [selected, loadRecords])

  // Deep-link support: when navigated here with `?record=<id>`, find the
  // record's parent operation, select it, and pop the detail drawer open.
  // Triggers when the map deep-links a record node.
  useEffect(() => {
    if (typeof window === "undefined" || operations.length === 0) return
    const params = new URLSearchParams(window.location.search)
    const recordId = params.get("record")
    if (!recordId) return
    let cancelled = false
    ;(async () => {
      try {
        const res = await fetch(`/api/operations/records/${recordId}`)
        if (!res.ok) return
        const { record } = await res.json()
        if (cancelled || !record) return
        const op = operations.find(o => o.id === record.operation_id)
        if (op) {
          setSelected(op)
          setOpenRecordId(recordId)
          // Strip the query param so refresh doesn't re-pop the drawer
          const url = new URL(window.location.href)
          url.searchParams.delete("record")
          window.history.replaceState({}, "", url.toString())
        }
      } catch { /* ignore */ }
    })()
    return () => { cancelled = true }
  }, [operations])

  // Keep selected in sync after operations reload
  useEffect(() => {
    if (selected) {
      const updated = operations.find(o => o.id === selected.id)
      if (updated) setSelected(updated)
    }
  }, [operations]) // eslint-disable-line react-hooks/exhaustive-deps

  async function createOperation() {
    if (!newName.trim()) return
    const res = await fetch("/api/operations", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        name: newName, codename: newCodename || null, description: newDesc,
        objectives: newObjectives, directives: newDirectives, priority: newPriority,
        visibility: newVisibility,
      }),
    })
    if (res.ok) {
      setNewName(""); setNewCodename(""); setNewDesc("")
      setNewObjectives(""); setNewDirectives(""); setNewPriority("medium")
      setNewVisibility("private")
      setShowNewOp(false)
      await loadOperations()
    }
  }

  async function cycleStatus(op: Operation) {
    const next = STATUS_CYCLE[(STATUS_CYCLE.indexOf(op.status) + 1) % STATUS_CYCLE.length]
    await fetch("/api/operations", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id: op.id, status: next }),
    })
    loadOperations()
  }

  async function deleteOperation(id: string) {
    await fetch("/api/operations", {
      method: "DELETE",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id }),
    })
    if (selected?.id === id) setSelected(null)
    loadOperations()
  }

  async function addRecord() {
    if (!selected || !recTitle.trim()) return
    await fetch("/api/operations/records", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        operation_id: selected.id, type: recType, title: recTitle,
        content: recContent, source: recSource, priority: recPriority,
      }),
    })
    setRecTitle(""); setRecContent(""); setRecType("note")
    setRecSource("manual"); setRecPriority("normal")
    setShowNewRec(false)
    loadRecords(selected.id)
    loadOperations()
  }

  async function assignAgent(agentId: string) {
    if (!selected) return
    await fetch("/api/operations/agents", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ operation_id: selected.id, agent_id: agentId }),
    })
    setShowAssign(false)
    loadOperations()
  }

  async function removeAgent(agentId: string) {
    if (!selected) return
    await fetch("/api/operations/agents", {
      method: "DELETE",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ operation_id: selected.id, agent_id: agentId }),
    })
    loadOperations()
  }

  const assignedIds = selected?.operation_agents?.map(a => a.agents.id) ?? []
  const unassigned  = allAgents.filter(a => !assignedIds.includes(a.id))

  return (
    <div className="flex flex-col md:flex-row h-[calc(100dvh-5rem)] md:h-screen bg-background text-foreground font-sans overflow-hidden">

      {/* ── Left panel: operations list ──────────────────────────────── */}
      <div className={`${selected ? "hidden md:flex" : "flex"} w-full md:w-72 md:shrink-0 flex-col border-b md:border-b-0 md:border-r border-border bg-card md:h-full`}>
        <div className="flex items-center justify-between px-4 py-3 border-b border-border">
          <div>
            <p className="text-xs font-medium text-muted-foreground">Nexus</p>
            <h1 className="text-sm font-semibold text-foreground">Operations</h1>
          </div>
          <button
            onClick={() => setShowNewOp(true)}
            className="w-7 h-7 flex items-center justify-center rounded border border-border text-muted-foreground hover:text-accent hover:border-accent/40 transition-colors"
          >
            <Plus size={14} />
          </button>
        </div>

        <div className="flex-1 overflow-y-auto">
          {loading ? (
            <p className="p-4 text-[11px] text-muted-foreground font-mono">Loading...</p>
          ) : operations.length === 0 ? (
            <div className="p-6 text-center mt-8">
              <Shield size={24} className="mx-auto mb-3 text-muted-foreground opacity-30" />
              <p className="text-[11px] text-muted-foreground font-mono">No operations.<br />Create one to begin.</p>
            </div>
          ) : operations.map(op => (
            <button
              key={op.id}
              onClick={() => setSelected(op)}
              className={`w-full text-left px-4 py-3 border-b border-border/50 hover:bg-accent/5 transition-colors group ${selected?.id === op.id ? "bg-accent/5 border-l-2 border-l-accent" : ""}`}
            >
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0">
                  <p className="text-[12px] font-medium text-foreground truncate">{op.name}</p>
                  {op.codename && (
                    <p className="text-[10px] font-mono text-accent truncate">// {op.codename}</p>
                  )}
                </div>
                <ChevronRight size={12} className="text-muted-foreground mt-0.5 shrink-0 opacity-0 group-hover:opacity-100" />
              </div>
              <div className="flex items-center gap-2 mt-1.5">
                <span className={`text-[10px] font-mono border px-1.5 py-0.5 rounded ${STATUS_STYLES[op.status]}`}>
                  {op.status}
                </span>
                <span className={`text-[10px] font-mono ${PRIORITY_STYLES[op.priority]}`}>
                  {op.priority}
                </span>
                <span className="text-[10px] text-muted-foreground ml-auto">
                  {op.operation_records?.[0]?.count ?? 0} records
                </span>
              </div>
            </button>
          ))}
        </div>
      </div>

      {/* ── Right panel: operation detail ────────────────────────────── */}
      <div className="flex-1 flex flex-col overflow-hidden">
        {!selected ? (
          <div className="flex-1 flex items-center justify-center">
            <div className="text-center">
              <Shield size={32} className="mx-auto mb-3 text-muted-foreground opacity-20" />
              <p className="text-sm font-mono text-muted-foreground">Select an operation</p>
            </div>
          </div>
        ) : (
          <>
            {/* Header */}
            <div className="flex items-start justify-between gap-2 px-4 md:px-6 py-3 md:py-4 border-b border-border shrink-0">
              <div className="min-w-0 flex-1">
                {/* Mobile back button */}
                <button
                  onClick={() => setSelected(null)}
                  className="md:hidden flex items-center gap-1 text-xs text-muted-foreground mb-1.5 hover:text-foreground"
                >
                  <ChevronRight size={14} className="rotate-180" /> All operations
                </button>
                <div className="flex items-center gap-2 md:gap-3 flex-wrap">
                  <h2 className="text-base md:text-lg font-semibold text-foreground">{selected.name}</h2>
                  {selected.codename && (
                    <span className="text-[11px] font-mono text-accent">// {selected.codename}</span>
                  )}
                  <button
                    onClick={() => cycleStatus(selected)}
                    title="Click to cycle status"
                    className={`text-[10px] font-mono border px-2 py-0.5 rounded cursor-pointer hover:opacity-80 transition-opacity ${STATUS_STYLES[selected.status]}`}
                  >
                    {selected.status}
                  </button>
                  <span className={`text-[10px] font-mono ${PRIORITY_STYLES[selected.priority]}`}>
                    {selected.priority} priority
                  </span>
                </div>
                {selected.description && (
                  <p className="text-[12px] text-muted-foreground mt-1">{selected.description}</p>
                )}
                <p className="text-[10px] font-mono text-muted-foreground mt-1 flex items-center gap-1">
                  <Clock size={10} />
                  Updated {timeAgo(selected.updated_at)}
                </p>
              </div>
              <div className="flex items-center gap-1 flex-shrink-0">
                <Link
                  href={`/dashboard/operations/${selected.id}`}
                  className="text-muted-foreground hover:text-foreground transition-colors p-1 text-xs flex items-center gap-1"
                  title="Open full view"
                >
                  Full view ↗
                </Link>
                <button
                  onClick={() => deleteOperation(selected.id)}
                  className="text-muted-foreground hover:text-destructive transition-colors p-1"
                  title="Delete operation"
                >
                  <Trash2 size={14} />
                </button>
              </div>
            </div>

            {/* Eve analyst bar — collapsible panel of 5 bulk actions */}
            <OperationBriefs operationId={selected.id} recordCount={records.length} />

            {/* Three-column body (stacked vertically on mobile) */}
            <div className="flex-1 overflow-y-auto md:overflow-hidden md:grid md:grid-cols-3 md:divide-x md:divide-border">

              {/* Col 1: Objectives + Directives */}
              <div className="p-4 md:p-5 md:overflow-y-auto space-y-6 border-b md:border-b-0 border-border">
                {selected.objectives ? (
                  <div>
                    <p className="text-xs font-medium text-muted-foreground mb-2">Objectives</p>
                    <p className="text-[12px] text-foreground/80 leading-relaxed whitespace-pre-wrap">{selected.objectives}</p>
                  </div>
                ) : null}
                {selected.directives ? (
                  <div>
                    <p className="text-xs font-medium text-muted-foreground mb-2">Directives</p>
                    <p className="text-[12px] text-foreground/80 leading-relaxed whitespace-pre-wrap">{selected.directives}</p>
                  </div>
                ) : null}
                {selected.tags?.length > 0 && (
                  <div>
                    <p className="text-xs font-medium text-muted-foreground mb-2">Tags</p>
                    <div className="flex flex-wrap gap-1">
                      {selected.tags.map(t => (
                        <span key={t} className="text-[10px] font-mono border border-border text-muted-foreground px-1.5 py-0.5 rounded">{t}</span>
                      ))}
                    </div>
                  </div>
                )}
                {!selected.objectives && !selected.directives && (
                  <p className="text-[11px] text-muted-foreground font-mono text-center mt-8">No objectives or directives set.</p>
                )}
              </div>

              {/* Col 2: Records — searchable, filterable, clickable */}
              <div className="flex flex-col p-4 md:p-5 md:overflow-hidden border-b md:border-b-0 border-border min-h-[400px] md:min-h-0">
                <RecordsList
                  records={records}
                  onOpen={id => setOpenRecordId(id)}
                  onAdd={() => setShowNewRec(true)}
                />
              </div>

              {/* Col 3: Assigned Agents */}
              <div className="p-4 md:p-5 md:overflow-y-auto">
                <div className="flex items-center justify-between mb-3">
                  <p className="text-xs font-medium text-muted-foreground">Personnel</p>
                  <button
                    onClick={() => setShowAssign(true)}
                    className="text-[10px] font-mono border border-border text-muted-foreground hover:text-accent hover:border-accent/40 px-2 py-0.5 rounded transition-colors flex items-center gap-1"
                  >
                    <UserPlus size={10} /> Assign
                  </button>
                </div>

                {/* Eve is always involved */}
                <div className="border border-accent/30 bg-accent/5 rounded p-3 mb-2">
                  <div className="flex items-center gap-2">
                    <Circle size={6} className="fill-accent text-accent shrink-0" />
                    <div>
                      <p className="text-[12px] font-medium text-accent">Eve</p>
                      <p className="text-[10px] text-muted-foreground font-mono">Command Intelligence · Always Active</p>
                    </div>
                  </div>
                </div>

                <div className="space-y-2">
                  {(selected.operation_agents ?? []).length === 0 ? (
                    <p className="text-[11px] text-muted-foreground font-mono text-center mt-4">No agents assigned.</p>
                  ) : selected.operation_agents.map(a => (
                    <div key={a.agents.id} className="group border border-border rounded p-3 hover:border-border/80 transition-colors">
                      <div className="flex items-center justify-between">
                        <div>
                          <p className="text-[12px] font-medium text-foreground">{a.agents.name}</p>
                          <p className="text-[10px] text-muted-foreground font-mono">{a.role_in_op ?? a.agents.role}</p>
                        </div>
                        <button
                          onClick={() => removeAgent(a.agents.id)}
                          className="opacity-0 group-hover:opacity-100 text-muted-foreground hover:text-destructive transition-colors"
                        >
                          <X size={11} />
                        </button>
                      </div>
                    </div>
                  ))}
                </div>
              </div>

            </div>
          </>
        )}
      </div>

      {/* ── Modal: New Operation ──────────────────────────────────────── */}
      {showNewOp && (
        <div className="fixed inset-0 bg-foreground/50 backdrop-blur-sm flex items-center justify-center z-50 p-4">
          <div className="bg-card border border-border rounded-lg w-full max-w-lg p-6 space-y-4">
            <div className="flex items-center justify-between">
              <h3 className="text-sm font-semibold text-foreground">New Operation</h3>
              <button onClick={() => setShowNewOp(false)} className="text-muted-foreground hover:text-foreground"><X size={16} /></button>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="col-span-2">
                <label className="text-xs font-medium text-muted-foreground">Name *</label>
                <input value={newName} onChange={e => setNewName(e.target.value)} placeholder="Operation name"
                  className="w-full mt-1 bg-background border border-border rounded px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:border-accent/50" />
              </div>
              <div>
                <label className="text-xs font-medium text-muted-foreground">Codename</label>
                <input value={newCodename} onChange={e => setNewCodename(e.target.value)} placeholder="GHOST, SHADE..."
                  className="w-full mt-1 bg-background border border-border rounded px-3 py-2 text-sm font-mono text-foreground placeholder:text-muted-foreground focus:outline-none focus:border-accent/50" />
              </div>
              <div>
                <label className="text-xs font-medium text-muted-foreground">Priority</label>
                <select value={newPriority} onChange={e => setNewPriority(e.target.value as OpPriority)}
                  className="w-full mt-1 bg-background border border-border rounded px-3 py-2 text-sm text-foreground focus:outline-none focus:border-accent/50">
                  {(["low","medium","high","critical"] as OpPriority[]).map(p => <option key={p} value={p}>{p}</option>)}
                </select>
              </div>
              <div>
                <label className="text-xs font-medium text-muted-foreground">Visibility</label>
                <select value={newVisibility} onChange={e => setNewVisibility(e.target.value as any)}
                  className="w-full mt-1 bg-background border border-border rounded px-3 py-2 text-sm text-foreground focus:outline-none focus:border-accent/50">
                  <option value="private">Private (Only You)</option>
                  <option value="shared">Shared (Specific Humans)</option>
                  <option value="group">Group</option>
                  <option value="public">Public (All Authenticated Humans)</option>
                </select>
              </div>
              <div className="col-span-2">
                <label className="text-xs font-medium text-muted-foreground">Description</label>
                <input value={newDesc} onChange={e => setNewDesc(e.target.value)} placeholder="What is this operation about?"
                  className="w-full mt-1 bg-background border border-border rounded px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:border-accent/50" />
              </div>
              <div className="col-span-2">
                <label className="text-xs font-medium text-muted-foreground">Objectives</label>
                <textarea value={newObjectives} onChange={e => setNewObjectives(e.target.value)} rows={2}
                  placeholder="What needs to be accomplished..."
                  className="w-full mt-1 bg-background border border-border rounded px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:border-accent/50 resize-none" />
              </div>
              <div className="col-span-2">
                <label className="text-xs font-medium text-muted-foreground">Directives</label>
                <textarea value={newDirectives} onChange={e => setNewDirectives(e.target.value)} rows={2}
                  placeholder="Rules Eve and agents must follow in this operation..."
                  className="w-full mt-1 bg-background border border-border rounded px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:border-accent/50 resize-none" />
              </div>
            </div>
            <div className="flex justify-end gap-2 pt-2">
              <button onClick={() => setShowNewOp(false)} className="text-[12px] border border-border text-muted-foreground px-4 py-1.5 rounded hover:bg-muted transition-colors">Cancel</button>
              <button onClick={createOperation} disabled={!newName.trim()} className="text-[12px] bg-accent text-accent-foreground font-medium px-4 py-1.5 rounded hover:opacity-90 transition-opacity disabled:opacity-40">Create</button>
            </div>
          </div>
        </div>
      )}

      {/* ── Modal: Add Record ─────────────────────────────────────────── */}
      {showNewRec && selected && (
        <div className="fixed inset-0 bg-foreground/50 backdrop-blur-sm flex items-center justify-center z-50 p-4">
          <div className="bg-card border border-border rounded-lg w-full max-w-md p-6 space-y-4">
            <div className="flex items-center justify-between">
              <h3 className="text-sm font-semibold text-foreground">Add Record</h3>
              <button onClick={() => setShowNewRec(false)} className="text-muted-foreground hover:text-foreground"><X size={16} /></button>
            </div>
            <div className="space-y-3">
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="text-xs font-medium text-muted-foreground">Type</label>
                  <select value={recType} onChange={e => setRecType(e.target.value as RecordType)}
                    className="w-full mt-1 bg-background border border-border rounded px-3 py-2 text-sm text-foreground focus:outline-none focus:border-accent/50">
                    {(["note","intel","data","finding","alert","file"] as RecordType[]).map(t => <option key={t} value={t}>{t}</option>)}
                  </select>
                </div>
                <div>
                  <label className="text-xs font-medium text-muted-foreground">Priority</label>
                  <select value={recPriority} onChange={e => setRecPriority(e.target.value)}
                    className="w-full mt-1 bg-background border border-border rounded px-3 py-2 text-sm text-foreground focus:outline-none focus:border-accent/50">
                    {["low","normal","high","critical"].map(p => <option key={p} value={p}>{p}</option>)}
                  </select>
                </div>
              </div>
              <div>
                <label className="text-xs font-medium text-muted-foreground">Title *</label>
                <input value={recTitle} onChange={e => setRecTitle(e.target.value)} placeholder="Record title"
                  className="w-full mt-1 bg-background border border-border rounded px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:border-accent/50" />
              </div>
              <div>
                <label className="text-xs font-medium text-muted-foreground">Content</label>
                <textarea value={recContent} onChange={e => setRecContent(e.target.value)} rows={4}
                  placeholder="Details, findings, data collected..."
                  className="w-full mt-1 bg-background border border-border rounded px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:border-accent/50 resize-none" />
              </div>
              <div>
                <label className="text-xs font-medium text-muted-foreground">Source</label>
                <input value={recSource} onChange={e => setRecSource(e.target.value)} placeholder="Eve, Shade, manual..."
                  className="w-full mt-1 bg-background border border-border rounded px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:border-accent/50" />
              </div>
            </div>
            <div className="flex justify-end gap-2 pt-2">
              <button onClick={() => setShowNewRec(false)} className="text-[12px] border border-border text-muted-foreground px-4 py-1.5 rounded hover:bg-muted transition-colors">Cancel</button>
              <button onClick={addRecord} disabled={!recTitle.trim()} className="text-[12px] bg-accent text-accent-foreground font-medium px-4 py-1.5 rounded hover:opacity-90 transition-opacity disabled:opacity-40">Add Record</button>
            </div>
          </div>
        </div>
      )}

      {/* ── Modal: Assign Agent ───────────────────────────────────────── */}
      {showAssign && selected && (
        <div className="fixed inset-0 bg-foreground/50 backdrop-blur-sm flex items-center justify-center z-50 p-4">
          <div className="bg-card border border-border rounded-lg w-full max-w-sm p-6 space-y-4">
            <div className="flex items-center justify-between">
              <h3 className="text-sm font-semibold text-foreground">Assign Agent</h3>
              <button onClick={() => setShowAssign(false)} className="text-muted-foreground hover:text-foreground"><X size={16} /></button>
            </div>
            {unassigned.length === 0 ? (
              <p className="text-[12px] text-muted-foreground font-mono text-center py-4">All available agents are already assigned.</p>
            ) : (
              <div className="space-y-2">
                {unassigned.map(a => (
                  <button key={a.id} onClick={() => assignAgent(a.id)}
                    className="w-full text-left border border-border rounded p-3 hover:border-accent/40 hover:bg-accent/5 transition-colors">
                    <p className="text-[12px] font-medium text-foreground">{a.name}</p>
                    <p className="text-[10px] text-muted-foreground font-mono">{a.role} · {a.status}</p>
                  </button>
                ))}
              </div>
            )}
          </div>
        </div>
      )}

      {/* ── Drawer: Record Detail ─────────────────────────────────────── */}
      {openRecordId && selected && (
        <RecordDetail
          recordId={openRecordId}
          onClose={() => setOpenRecordId(null)}
          onChanged={() => {
            loadRecords(selected.id)
            loadOperations()
          }}
        />
      )}

    </div>
  )
}
