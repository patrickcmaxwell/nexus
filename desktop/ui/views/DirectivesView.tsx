import React, { useEffect, useState } from 'react'
import { Shield, BookOpen, AlertTriangle, Plus, Trash2, Power } from 'lucide-react'

const NEXUS = 'http://localhost:3000'

interface Directive {
  id: string
  type: string
  title: string
  content: string
  priority: number
  target: string
  is_active: boolean
}

const TYPE_META: Record<string, { icon: React.ReactNode; color: string }> = {
  directive: { icon: <Shield size={12} />,         color: 'text-[#00d4ff] border-[#00d4ff]/20 bg-[#00d4ff]/5' },
  protocol:  { icon: <BookOpen size={12} />,       color: 'text-amber-400 border-amber-400/20 bg-amber-400/5' },
  rule:      { icon: <AlertTriangle size={12} />,  color: 'text-rose-400 border-rose-400/20 bg-rose-400/5' },
}

function apiHeaders(sessionId: string) {
  return { 'Content-Type': 'application/json', Authorization: `Bearer ${sessionId}` }
}

export function DirectivesView({ sessionId }: { sessionId: string }) {
  const [items, setItems]     = useState<Directive[]>([])
  const [loading, setLoading] = useState(true)
  const [selected, setSelected] = useState<Directive | null>(null)
  const [filter, setFilter]   = useState<string>('all')
  const [showCreate, setShowCreate] = useState(false)
  const [saving, setSaving]   = useState(false)

  const [form, setForm] = useState({ type: 'directive', title: '', content: '', priority: '0', target: 'all' })

  const load = () =>
    fetch(`${NEXUS}/api/eve/directives`, { headers: apiHeaders(sessionId) })
      .then(r => r.json())
      .then(d => { setItems(Array.isArray(d) ? d : d.directives ?? []); setLoading(false) })
      .catch(() => setLoading(false))

  useEffect(() => { load() }, [sessionId])

  async function createDirective() {
    if (!form.title.trim() || !form.content.trim()) return
    setSaving(true)
    try {
      const res = await fetch(`${NEXUS}/api/eve/directives`, {
        method: 'POST',
        headers: apiHeaders(sessionId),
        body: JSON.stringify({ ...form, priority: parseInt(form.priority) || 0 }),
      })
      if (res.ok) {
        setShowCreate(false)
        setForm({ type: 'directive', title: '', content: '', priority: '0', target: 'all' })
        await load()
      }
    } finally { setSaving(false) }
  }

  async function toggleActive(item: Directive) {
    await fetch(`${NEXUS}/api/eve/directives`, {
      method: 'PATCH',
      headers: apiHeaders(sessionId),
      body: JSON.stringify({ id: item.id, is_active: !item.is_active }),
    })
    const updated = { ...item, is_active: !item.is_active }
    setItems(prev => prev.map(d => d.id === item.id ? updated : d))
    if (selected?.id === item.id) setSelected(updated)
  }

  async function deleteDirective(id: string) {
    if (!confirm('Delete this directive?')) return
    await fetch(`${NEXUS}/api/eve/directives`, {
      method: 'DELETE',
      headers: apiHeaders(sessionId),
      body: JSON.stringify({ id }),
    })
    setItems(prev => prev.filter(d => d.id !== id))
    if (selected?.id === id) setSelected(null)
  }

  const filtered = filter === 'all' ? items : items.filter(i => i.type === filter)
  const meta = (t: string) => TYPE_META[t] ?? TYPE_META.directive

  return (
    <div className="flex-1 flex overflow-hidden">

      {/* ── List ─────────────────────────────────────────────────────────── */}
      <div className="w-72 flex-shrink-0 flex flex-col border-r border-white/[0.04] overflow-hidden">
        <div className="px-5 py-4 border-b border-white/[0.04]">
          <div className="flex items-center justify-between mb-3">
            <h2 className="text-[11px] font-mono tracking-[0.3em] text-white/30 uppercase">Directives</h2>
            <button
              onClick={() => setShowCreate(true)}
              className="flex items-center gap-1.5 text-[10px] font-mono uppercase px-3 py-1.5 border border-[#00d4ff]/20 text-[#00d4ff]/60 hover:bg-[#00d4ff]/10 rounded-lg transition-all"
            >
              <Plus size={11} /> New
            </button>
          </div>
          <div className="flex gap-1">
            {['all', 'directive', 'protocol', 'rule'].map(f => (
              <button key={f} onClick={() => setFilter(f)}
                className={`text-[9px] font-mono uppercase px-2 py-0.5 rounded border transition-colors ${
                  filter === f ? 'border-[#00d4ff]/30 text-[#00d4ff]/70 bg-[#00d4ff]/5' : 'border-white/8 text-white/25 hover:text-white/50'
                }`}>
                {f}
              </button>
            ))}
          </div>
        </div>

        <div className="flex-1 overflow-y-auto">
          {loading && <p className="text-[11px] font-mono text-white/20 p-5">Loading...</p>}
          {!loading && filtered.length === 0 && (
            <p className="text-[11px] font-mono text-white/20 p-5">No {filter === 'all' ? 'directives' : filter + 's'} found.</p>
          )}
          {filtered
            .sort((a, b) => b.priority - a.priority)
            .map(d => {
              const m = meta(d.type)
              return (
                <button key={d.id} onClick={() => setSelected(d)}
                  className={`w-full text-left px-5 py-4 border-b border-white/[0.03] hover:bg-white/3 transition-colors ${selected?.id === d.id ? 'bg-white/4' : ''} ${!d.is_active ? 'opacity-40' : ''}`}>
                  <div className="flex items-start justify-between gap-2 mb-1.5">
                    <span className="text-sm text-white/80 leading-tight">{d.title}</span>
                    <span className={`flex-shrink-0 flex items-center gap-1 text-[9px] font-mono uppercase px-1.5 py-0.5 rounded border ${m.color}`}>
                      {m.icon}{d.type}
                    </span>
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="text-[10px] text-white/20">P{d.priority}</span>
                    {!d.is_active && <span className="text-[9px] font-mono text-white/20 border border-white/10 px-1 rounded">INACTIVE</span>}
                  </div>
                </button>
              )
            })}
        </div>
      </div>

      {/* ── Detail ───────────────────────────────────────────────────────── */}
      <div className="flex-1 overflow-y-auto p-8">
        {!selected ? (
          <div className="h-full flex items-center justify-center">
            <p className="text-[11px] font-mono text-white/15 tracking-widest uppercase">Select a directive</p>
          </div>
        ) : (
          <div className="max-w-2xl space-y-6">
            <div className="flex items-start justify-between gap-4">
              <div>
                <div className="flex items-center gap-3 mb-2">
                  <span className={`flex items-center gap-1 text-[9px] font-mono uppercase px-2 py-1 rounded border ${meta(selected.type).color}`}>
                    {meta(selected.type).icon}{selected.type}
                  </span>
                  <span className="text-[10px] font-mono text-white/25">Priority {selected.priority}</span>
                  {selected.target && <span className="text-[10px] font-mono text-white/25">· {selected.target}</span>}
                  {!selected.is_active && (
                    <span className="text-[9px] font-mono uppercase text-white/20 border border-white/10 px-1.5 py-0.5 rounded">Inactive</span>
                  )}
                </div>
                <h1 className="text-2xl text-white/90 font-light">{selected.title}</h1>
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={() => toggleActive(selected)}
                  className={`flex items-center gap-1.5 text-[10px] font-mono uppercase px-3 py-1.5 border rounded-lg transition-all ${
                    selected.is_active
                      ? 'border-amber-400/25 text-amber-400/60 hover:bg-amber-400/10'
                      : 'border-[#00ff88]/25 text-[#00ff88]/60 hover:bg-[#00ff88]/10'
                  }`}
                >
                  <Power size={11} />
                  {selected.is_active ? 'Deactivate' : 'Activate'}
                </button>
                <button
                  onClick={() => deleteDirective(selected.id)}
                  className="flex items-center gap-1.5 text-[10px] font-mono uppercase px-3 py-1.5 border border-red-500/20 text-red-400/50 hover:bg-red-500/10 hover:text-red-400 rounded-lg transition-all"
                >
                  <Trash2 size={11} /> Delete
                </button>
              </div>
            </div>

            <div>
              <p className="text-[10px] font-mono tracking-widest text-white/25 uppercase mb-2">Content</p>
              <p className="text-sm text-white/60 leading-relaxed whitespace-pre-wrap select-text cursor-text">{selected.content}</p>
            </div>
          </div>
        )}
      </div>

      {/* ── Create Modal ──────────────────────────────────────────────────── */}
      {showCreate && (
        <div className="fixed inset-0 bg-black/70 flex items-center justify-center z-50" onClick={() => setShowCreate(false)}>
          <div className="bg-[#0a0a0a] border border-white/10 rounded-2xl p-8 w-full max-w-lg" onClick={e => e.stopPropagation()}>
            <h2 className="text-[11px] font-mono tracking-[0.3em] text-white/40 uppercase mb-6">New Directive</h2>

            <div className="space-y-4">
              <div className="flex gap-4">
                <FormField label="Type">
                  <select value={form.type} onChange={e => setForm(f => ({ ...f, type: e.target.value }))}
                    className="w-full bg-white/5 border border-white/10 rounded-xl px-3 py-2.5 text-sm text-white/80 focus:outline-none focus:border-white/25">
                    <option value="directive">Directive</option>
                    <option value="protocol">Protocol</option>
                    <option value="rule">Rule</option>
                  </select>
                </FormField>
                <FormField label="Priority (0–10)">
                  <input type="number" min="0" max="10" value={form.priority} onChange={e => setForm(f => ({ ...f, priority: e.target.value }))}
                    className="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-2.5 text-sm text-white/80 focus:outline-none focus:border-white/25" />
                </FormField>
              </div>
              <FormField label="Title *">
                <input autoFocus value={form.title} onChange={e => setForm(f => ({ ...f, title: e.target.value }))}
                  className="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-2.5 text-sm text-white/80 placeholder:text-white/20 focus:outline-none focus:border-white/25"
                  placeholder="Directive title" />
              </FormField>
              <FormField label="Target">
                <input value={form.target} onChange={e => setForm(f => ({ ...f, target: e.target.value }))}
                  className="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-2.5 text-sm text-white/80 placeholder:text-white/20 focus:outline-none focus:border-white/25"
                  placeholder="all, eve, agents..." />
              </FormField>
              <FormField label="Content *">
                <textarea value={form.content} onChange={e => setForm(f => ({ ...f, content: e.target.value }))} rows={4}
                  className="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-2.5 text-sm text-white/80 placeholder:text-white/20 focus:outline-none focus:border-white/25 resize-none"
                  placeholder="Directive content and instructions..." />
              </FormField>
            </div>

            <div className="flex justify-end gap-3 mt-6">
              <button onClick={() => setShowCreate(false)}
                className="px-4 py-2 text-[11px] font-mono uppercase text-white/30 hover:text-white/60 transition-colors">
                Cancel
              </button>
              <button onClick={createDirective} disabled={!form.title.trim() || !form.content.trim() || saving}
                className="px-5 py-2 text-[11px] font-mono uppercase border border-[#00d4ff]/25 text-[#00d4ff]/70 hover:bg-[#00d4ff]/10 rounded-xl transition-all disabled:opacity-30">
                {saving ? 'Saving...' : 'Create Directive'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

function FormField({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex-1">
      <p className="text-[10px] font-mono text-white/30 uppercase mb-1.5">{label}</p>
      {children}
    </div>
  )
}
