import React, { useEffect, useState } from 'react'
import { Zap, Clock, CheckCircle, XCircle, PauseCircle, Plus, Trash2, ChevronDown } from 'lucide-react'

const NEXUS = 'http://localhost:3000'

interface Operation {
  id: string
  name: string
  codename: string | null
  description: string
  status: string
  priority: string
  objectives: string
  created_at: string
  updated_at: string
}

const STATUS_OPTIONS = ['planning', 'active', 'paused', 'complete', 'aborted']
const PRIORITY_OPTIONS = ['low', 'medium', 'high', 'critical']

const STATUS_META: Record<string, { icon: React.ReactNode; color: string }> = {
  active:   { icon: <Zap size={11} />,         color: 'text-[#00ff88] border-[#00ff88]/25 bg-[#00ff88]/8' },
  planning: { icon: <Clock size={11} />,        color: 'text-amber-400 border-amber-400/25 bg-amber-400/8' },
  paused:   { icon: <PauseCircle size={11} />,  color: 'text-white/35 border-white/15 bg-white/4' },
  complete: { icon: <CheckCircle size={11} />,  color: 'text-[#00d4ff] border-[#00d4ff]/25 bg-[#00d4ff]/8' },
  aborted:  { icon: <XCircle size={11} />,      color: 'text-red-400 border-red-400/25 bg-red-400/8' },
}

const PRIORITY_COLOR: Record<string, string> = {
  critical: 'text-red-400',
  high:     'text-amber-400',
  medium:   'text-[#00d4ff]',
  low:      'text-white/30',
}

function apiHeaders(sessionId: string) {
  return { 'Content-Type': 'application/json', Authorization: `Bearer ${sessionId}` }
}

export function OpsView({ sessionId }: { sessionId: string }) {
  const [ops, setOps]           = useState<Operation[]>([])
  const [loading, setLoading]   = useState(true)
  const [selected, setSelected] = useState<Operation | null>(null)
  const [showCreate, setShowCreate] = useState(false)
  const [saving, setSaving]     = useState(false)
  const [deleting, setDeleting] = useState(false)

  const [form, setForm] = useState({ name: '', codename: '', description: '', objectives: '', status: 'planning', priority: 'medium' })

  const load = () =>
    fetch(`${NEXUS}/api/operations`, { headers: apiHeaders(sessionId) })
      .then(r => r.json())
      .then(d => { setOps(Array.isArray(d) ? d : d.operations ?? []); setLoading(false) })
      .catch(() => setLoading(false))

  useEffect(() => { load() }, [sessionId])

  async function createOp() {
    if (!form.name.trim()) return
    setSaving(true)
    try {
      const res = await fetch(`${NEXUS}/api/operations`, {
        method: 'POST',
        headers: apiHeaders(sessionId),
        body: JSON.stringify({ ...form, name: form.name.trim() }),
      })
      if (res.ok) {
        setShowCreate(false)
        setForm({ name: '', codename: '', description: '', objectives: '', status: 'planning', priority: 'medium' })
        await load()
      }
    } finally { setSaving(false) }
  }

  async function updateField(id: string, field: string, value: string) {
    await fetch(`${NEXUS}/api/operations`, {
      method: 'PATCH',
      headers: apiHeaders(sessionId),
      body: JSON.stringify({ id, [field]: value }),
    })
    setOps(prev => prev.map(o => o.id === id ? { ...o, [field]: value } : o))
    if (selected?.id === id) setSelected(prev => prev ? { ...prev, [field]: value } : null)
  }

  async function deleteOp(id: string) {
    if (!confirm('Delete this operation? This cannot be undone.')) return
    setDeleting(true)
    try {
      await fetch(`${NEXUS}/api/operations`, {
        method: 'DELETE',
        headers: apiHeaders(sessionId),
        body: JSON.stringify({ id }),
      })
      setOps(prev => prev.filter(o => o.id !== id))
      if (selected?.id === id) setSelected(null)
    } finally { setDeleting(false) }
  }

  const meta = (s: string) => STATUS_META[s] ?? STATUS_META.planning

  return (
    <div className="flex-1 flex overflow-hidden">

      {/* ── List ─────────────────────────────────────────────────────────── */}
      <div className="w-80 flex-shrink-0 flex flex-col border-r border-white/[0.04] overflow-hidden">
        <div className="px-5 py-4 border-b border-white/[0.04] flex items-center justify-between">
          <div>
            <h2 className="text-[11px] font-mono tracking-[0.3em] text-white/30 uppercase">Operations</h2>
            <p className="text-xs text-white/20 mt-0.5">{ops.length} total</p>
          </div>
          <button
            onClick={() => setShowCreate(true)}
            className="flex items-center gap-1.5 text-[10px] font-mono uppercase px-3 py-1.5 border border-[#00d4ff]/20 text-[#00d4ff]/60 hover:bg-[#00d4ff]/10 rounded-lg transition-all"
          >
            <Plus size={11} /> New
          </button>
        </div>

        <div className="flex-1 overflow-y-auto">
          {loading && <p className="text-[11px] font-mono text-white/20 p-5">Loading...</p>}
          {!loading && ops.length === 0 && (
            <p className="text-[11px] font-mono text-white/20 p-5">No operations. Create one above.</p>
          )}
          {ops.map(op => {
            const m = meta(op.status)
            return (
              <button
                key={op.id}
                onClick={() => setSelected(op)}
                className={`w-full text-left px-5 py-4 border-b border-white/[0.03] hover:bg-white/3 transition-colors ${selected?.id === op.id ? 'bg-white/4' : ''}`}
              >
                <div className="flex items-start justify-between gap-2">
                  <span className="text-sm text-white/80 font-medium leading-tight">{op.name}</span>
                  <span className={`flex-shrink-0 flex items-center gap-1 text-[9px] font-mono uppercase px-1.5 py-0.5 rounded border ${m.color}`}>
                    {m.icon}{op.status}
                  </span>
                </div>
                <div className="flex items-center gap-2 mt-1.5">
                  <span className={`text-[10px] font-mono uppercase ${PRIORITY_COLOR[op.priority] ?? 'text-white/30'}`}>{op.priority}</span>
                  {op.codename && <span className="text-[10px] text-white/20 truncate">· {op.codename}</span>}
                </div>
              </button>
            )
          })}
        </div>
      </div>

      {/* ── Detail / Edit ────────────────────────────────────────────────── */}
      <div className="flex-1 overflow-y-auto p-8">
        {!selected ? (
          <div className="h-full flex items-center justify-center">
            <p className="text-[11px] font-mono text-white/15 tracking-widest uppercase">Select an operation</p>
          </div>
        ) : (
          <div className="max-w-2xl space-y-6">

            {/* Header */}
            <div className="flex items-start justify-between">
              <div>
                <h1 className="text-2xl text-white/90 font-light">{selected.name}</h1>
                {selected.codename && <p className="text-[11px] font-mono text-white/25 mt-1 tracking-widest uppercase">{selected.codename}</p>}
              </div>
              <button
                onClick={() => deleteOp(selected.id)}
                disabled={deleting}
                className="flex items-center gap-1.5 text-[10px] font-mono uppercase px-3 py-1.5 border border-red-500/20 text-red-400/50 hover:bg-red-500/10 hover:text-red-400 rounded-lg transition-all disabled:opacity-30"
              >
                <Trash2 size={11} /> Delete
              </button>
            </div>

            {/* Status + Priority inline controls */}
            <div className="flex items-center gap-4">
              <div>
                <p className="text-[10px] font-mono text-white/25 uppercase mb-1.5">Status</p>
                <div className="relative">
                  <select
                    value={selected.status}
                    onChange={e => updateField(selected.id, 'status', e.target.value)}
                    className="appearance-none bg-white/5 border border-white/10 rounded-lg px-3 py-1.5 text-sm text-white/70 pr-7 focus:outline-none focus:border-white/25 cursor-pointer"
                  >
                    {STATUS_OPTIONS.map(s => <option key={s} value={s}>{s}</option>)}
                  </select>
                  <ChevronDown size={12} className="absolute right-2 top-1/2 -translate-y-1/2 text-white/30 pointer-events-none" />
                </div>
              </div>
              <div>
                <p className="text-[10px] font-mono text-white/25 uppercase mb-1.5">Priority</p>
                <div className="relative">
                  <select
                    value={selected.priority}
                    onChange={e => updateField(selected.id, 'priority', e.target.value)}
                    className="appearance-none bg-white/5 border border-white/10 rounded-lg px-3 py-1.5 text-sm text-white/70 pr-7 focus:outline-none focus:border-white/25 cursor-pointer"
                  >
                    {PRIORITY_OPTIONS.map(p => <option key={p} value={p}>{p}</option>)}
                  </select>
                  <ChevronDown size={12} className="absolute right-2 top-1/2 -translate-y-1/2 text-white/30 pointer-events-none" />
                </div>
              </div>
            </div>

            <EditableField
              label="Description"
              value={selected.description}
              onSave={v => updateField(selected.id, 'description', v)}
            />
            <EditableField
              label="Objectives"
              value={selected.objectives}
              onSave={v => updateField(selected.id, 'objectives', v)}
            />
          </div>
        )}
      </div>

      {/* ── Create Modal ──────────────────────────────────────────────────── */}
      {showCreate && (
        <div className="fixed inset-0 bg-black/70 flex items-center justify-center z-50" onClick={() => setShowCreate(false)}>
          <div className="bg-[#0a0a0a] border border-white/10 rounded-2xl p-8 w-full max-w-lg" onClick={e => e.stopPropagation()}>
            <h2 className="text-[11px] font-mono tracking-[0.3em] text-white/40 uppercase mb-6">New Operation</h2>

            <div className="space-y-4">
              <Field label="Name *">
                <input autoFocus value={form.name} onChange={e => setForm(f => ({ ...f, name: e.target.value }))}
                  onKeyDown={e => e.key === 'Enter' && createOp()}
                  className="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-2.5 text-sm text-white/80 placeholder:text-white/20 focus:outline-none focus:border-white/25"
                  placeholder="Operation name" />
              </Field>
              <Field label="Codename">
                <input value={form.codename} onChange={e => setForm(f => ({ ...f, codename: e.target.value }))}
                  className="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-2.5 text-sm text-white/80 placeholder:text-white/20 focus:outline-none focus:border-white/25"
                  placeholder="OPERATION_NAME" />
              </Field>
              <div className="flex gap-4">
                <Field label="Status">
                  <select value={form.status} onChange={e => setForm(f => ({ ...f, status: e.target.value }))}
                    className="w-full bg-white/5 border border-white/10 rounded-xl px-3 py-2.5 text-sm text-white/80 focus:outline-none focus:border-white/25">
                    {STATUS_OPTIONS.map(s => <option key={s} value={s}>{s}</option>)}
                  </select>
                </Field>
                <Field label="Priority">
                  <select value={form.priority} onChange={e => setForm(f => ({ ...f, priority: e.target.value }))}
                    className="w-full bg-white/5 border border-white/10 rounded-xl px-3 py-2.5 text-sm text-white/80 focus:outline-none focus:border-white/25">
                    {PRIORITY_OPTIONS.map(p => <option key={p} value={p}>{p}</option>)}
                  </select>
                </Field>
              </div>
              <Field label="Description">
                <textarea value={form.description} onChange={e => setForm(f => ({ ...f, description: e.target.value }))} rows={2}
                  className="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-2.5 text-sm text-white/80 placeholder:text-white/20 focus:outline-none focus:border-white/25 resize-none"
                  placeholder="Brief description..." />
              </Field>
              <Field label="Objectives">
                <textarea value={form.objectives} onChange={e => setForm(f => ({ ...f, objectives: e.target.value }))} rows={2}
                  className="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-2.5 text-sm text-white/80 placeholder:text-white/20 focus:outline-none focus:border-white/25 resize-none"
                  placeholder="Key objectives..." />
              </Field>
            </div>

            <div className="flex justify-end gap-3 mt-6">
              <button onClick={() => setShowCreate(false)}
                className="px-4 py-2 text-[11px] font-mono uppercase text-white/30 hover:text-white/60 transition-colors">
                Cancel
              </button>
              <button onClick={createOp} disabled={!form.name.trim() || saving}
                className="px-5 py-2 text-[11px] font-mono uppercase border border-[#00d4ff]/25 text-[#00d4ff]/70 hover:bg-[#00d4ff]/10 rounded-xl transition-all disabled:opacity-30">
                {saving ? 'Creating...' : 'Create Operation'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex-1">
      <p className="text-[10px] font-mono text-white/30 uppercase mb-1.5">{label}</p>
      {children}
    </div>
  )
}

function EditableField({ label, value, onSave }: { label: string; value: string; onSave: (v: string) => void }) {
  const [editing, setEditing] = useState(false)
  const [draft, setDraft]     = useState(value)

  useEffect(() => { setDraft(value); setEditing(false) }, [value])

  function save() { onSave(draft); setEditing(false) }

  return (
    <div>
      <div className="flex items-center justify-between mb-2">
        <p className="text-[10px] font-mono tracking-widest text-white/25 uppercase">{label}</p>
        {!editing
          ? <button onClick={() => setEditing(true)} className="text-[10px] font-mono text-white/20 hover:text-[#00d4ff]/60 transition-colors">Edit</button>
          : <div className="flex gap-2">
              <button onClick={() => { setDraft(value); setEditing(false) }} className="text-[10px] font-mono text-white/20 hover:text-white/50 transition-colors">Cancel</button>
              <button onClick={save} className="text-[10px] font-mono text-[#00d4ff]/60 hover:text-[#00d4ff] transition-colors">Save</button>
            </div>
        }
      </div>
      {editing ? (
        <textarea
          autoFocus
          value={draft}
          onChange={e => setDraft(e.target.value)}
          rows={4}
          className="w-full bg-white/5 border border-white/15 rounded-xl px-4 py-3 text-sm text-white/80 focus:outline-none focus:border-white/25 resize-none"
        />
      ) : (
        <p className="text-sm text-white/55 leading-relaxed whitespace-pre-wrap select-text cursor-text">
          {value || <span className="text-white/20 italic">Not set</span>}
        </p>
      )}
    </div>
  )
}
