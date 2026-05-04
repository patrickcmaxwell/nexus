import React, { useEffect, useRef, useState } from 'react'
import { Bot, Zap, WifiOff, Clock, Plus, Trash2, Play, Square, Send, MessageSquare, Settings } from 'lucide-react'

const NEXUS = 'http://localhost:3000'

interface Agent {
  id: string
  name: string
  role: string
  status: string
  personality: string
  capabilities: string[]
  directives: string
  total_findings?: number
  last_scanned_at?: string
}

const STATUS_META: Record<string, { icon: React.ReactNode; color: string; label: string }> = {
  active:  { icon: <Zap size={11} />,     color: 'text-[#00ff88] border-[#00ff88]/25 bg-[#00ff88]/8',  label: 'ACTIVE' },
  standby: { icon: <Clock size={11} />,   color: 'text-amber-400 border-amber-400/25 bg-amber-400/8',  label: 'STANDBY' },
  offline: { icon: <WifiOff size={11} />, color: 'text-white/30 border-white/12 bg-white/4',           label: 'OFFLINE' },
}

function apiHeaders(sessionId: string) {
  return { 'Content-Type': 'application/json', Authorization: `Bearer ${sessionId}` }
}

interface ChatMsg { role: 'user' | 'agent'; content: string }

export function AgentsView({ sessionId }: { sessionId: string }) {
  const [agents, setAgents]     = useState<Agent[]>([])
  const [loading, setLoading]   = useState(true)
  const [selected, setSelected] = useState<Agent | null>(null)
  const [showCreate, setShowCreate] = useState(false)
  const [running, setRunning]   = useState<string | null>(null)
  const [saving, setSaving]     = useState(false)
  const [tab, setTab]           = useState<'profile' | 'chat'>('profile')
  const [chatHistory, setChatHistory] = useState<Record<string, ChatMsg[]>>({})
  const [chatInput, setChatInput]     = useState('')
  const [chatSending, setChatSending] = useState(false)
  const chatBottomRef = useRef<HTMLDivElement>(null)

  const [form, setForm] = useState({ name: '', role: '', personality: '', directives: '', capabilities: '', status: 'standby' })

  const load = () =>
    fetch(`${NEXUS}/api/agents`, { headers: apiHeaders(sessionId) })
      .then(r => r.json())
      .then(d => { setAgents(Array.isArray(d) ? d : d.agents ?? []); setLoading(false) })
      .catch(() => setLoading(false))

  useEffect(() => { load() }, [sessionId])

  async function createAgent() {
    if (!form.name.trim() || !form.role.trim()) return
    setSaving(true)
    try {
      const capabilities = form.capabilities.split(',').map(c => c.trim()).filter(Boolean)
      const res = await fetch(`${NEXUS}/api/agents`, {
        method: 'POST',
        headers: apiHeaders(sessionId),
        body: JSON.stringify({ ...form, name: form.name.trim(), role: form.role.trim(), capabilities }),
      })
      if (res.ok) {
        setShowCreate(false)
        setForm({ name: '', role: '', personality: '', directives: '', capabilities: '', status: 'standby' })
        await load()
      }
    } finally { setSaving(false) }
  }

  async function toggleStatus(agent: Agent) {
    const newStatus = agent.status === 'active' ? 'standby' : 'active'
    await fetch(`${NEXUS}/api/agents`, {
      method: 'PATCH',
      headers: apiHeaders(sessionId),
      body: JSON.stringify({ id: agent.id, status: newStatus }),
    })
    setAgents(prev => prev.map(a => a.id === agent.id ? { ...a, status: newStatus } : a))
    if (selected?.id === agent.id) setSelected(prev => prev ? { ...prev, status: newStatus } : null)
  }

  async function runAgent(id: string) {
    setRunning(id)
    try {
      await fetch(`${NEXUS}/api/agents/run`, {
        method: 'POST',
        headers: apiHeaders(sessionId),
        body: JSON.stringify({ agentId: id }),
      })
      await load()
    } finally { setRunning(null) }
  }

  async function deleteAgent(id: string) {
    if (!confirm('Delete this agent?')) return
    await fetch(`${NEXUS}/api/agents`, {
      method: 'DELETE',
      headers: apiHeaders(sessionId),
      body: JSON.stringify({ id }),
    })
    setAgents(prev => prev.filter(a => a.id !== id))
    if (selected?.id === id) setSelected(null)
  }

  async function updateField(id: string, field: string, value: string) {
    await fetch(`${NEXUS}/api/agents`, {
      method: 'PATCH',
      headers: apiHeaders(sessionId),
      body: JSON.stringify({ id, [field]: value }),
    })
    setAgents(prev => prev.map(a => a.id === id ? { ...a, [field]: value } : a))
    if (selected?.id === id) setSelected(prev => prev ? { ...prev, [field]: value } : null)
  }

  useEffect(() => {
    chatBottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [chatHistory, selected])

  async function sendChat() {
    if (!chatInput.trim() || !selected || chatSending) return
    const msg = chatInput.trim()
    setChatInput('')
    setChatSending(true)
    const agentId = selected.id
    const prev = chatHistory[agentId] ?? []
    const updated: ChatMsg[] = [...prev, { role: 'user', content: msg }]
    setChatHistory(h => ({ ...h, [agentId]: updated }))
    try {
      const history = prev.map(m => ({ role: m.role === 'agent' ? 'assistant' : 'user', content: m.content }))
      const res = await fetch(`${NEXUS}/api/agents/chat`, {
        method: 'POST',
        headers: apiHeaders(sessionId),
        body: JSON.stringify({ agentId, message: msg, history }),
      })
      const d = await res.json()
      const reply = d.response ?? 'No response.'
      setChatHistory(h => ({ ...h, [agentId]: [...(h[agentId] ?? []), { role: 'agent', content: reply }] }))
    } catch {
      setChatHistory(h => ({ ...h, [agentId]: [...(h[agentId] ?? []), { role: 'agent', content: 'Comms link failed.' }] }))
    } finally { setChatSending(false) }
  }

  const meta = (s: string) => STATUS_META[s] ?? STATUS_META.offline

  return (
    <div className="flex-1 flex overflow-hidden">

      {/* ── List ─────────────────────────────────────────────────────────── */}
      <div className="w-72 flex-shrink-0 flex flex-col border-r border-white/[0.04] overflow-hidden">
        <div className="px-5 py-4 border-b border-white/[0.04] flex items-center justify-between">
          <div>
            <h2 className="text-[11px] font-mono tracking-[0.3em] text-white/30 uppercase">Agents Roster</h2>
            <p className="text-xs text-white/20 mt-0.5">{agents.length} deployed</p>
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
          {!loading && agents.length === 0 && (
            <p className="text-[11px] font-mono text-white/20 p-5">No agents deployed. Create one above.</p>
          )}
          {agents.map(a => {
            const m = meta(a.status)
            return (
              <button
                key={a.id}
                onClick={() => { setSelected(a); setTab('chat') }}
                className={`w-full text-left px-5 py-4 border-b border-white/[0.03] hover:bg-white/3 transition-colors ${selected?.id === a.id ? 'bg-white/4' : ''}`}
              >
                <div className="flex items-center gap-2 mb-1.5">
                  <Bot size={13} className="text-white/25 flex-shrink-0" />
                  <span className="text-sm text-white/80 font-medium truncate">{a.name}</span>
                </div>
                <div className="flex items-center gap-2">
                  <span className={`flex items-center gap-1 text-[9px] font-mono uppercase px-1.5 py-0.5 rounded border ${m.color}`}>
                    {m.icon}{m.label}
                  </span>
                  <span className="text-[10px] text-white/25 truncate">{a.role}</span>
                </div>
              </button>
            )
          })}
        </div>
      </div>

      {/* ── Detail ───────────────────────────────────────────────────────── */}
      <div className="flex-1 flex flex-col overflow-hidden">
        {!selected ? (
          <div className="flex-1 flex items-center justify-center">
            <p className="text-[11px] font-mono text-white/15 tracking-widest uppercase">Select an agent</p>
          </div>
        ) : (
          <>
            {/* Agent header */}
            <div className="px-6 py-4 border-b border-white/[0.04] flex items-start justify-between flex-shrink-0">
              <div className="flex items-start gap-4">
                <div>
                  <div className="flex items-center gap-2 mb-1">
                    <span className={`flex items-center gap-1 text-[9px] font-mono uppercase px-1.5 py-0.5 rounded border ${meta(selected.status).color}`}>
                      {meta(selected.status).icon}{meta(selected.status).label}
                    </span>
                    {selected.total_findings != null && (
                      <span className="text-[9px] font-mono text-white/20">{selected.total_findings} findings</span>
                    )}
                  </div>
                  <h2 className="text-lg text-white/85 font-medium">{selected.name}</h2>
                  <p className="text-xs text-white/30 mt-0.5">{selected.role}</p>
                </div>
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={() => toggleStatus(selected)}
                  className={`flex items-center gap-1.5 text-[10px] font-mono uppercase px-3 py-1.5 border rounded-lg transition-all ${
                    selected.status === 'active'
                      ? 'border-amber-400/25 text-amber-400/60 hover:bg-amber-400/10'
                      : 'border-[#00ff88]/25 text-[#00ff88]/60 hover:bg-[#00ff88]/10'
                  }`}
                >
                  {selected.status === 'active' ? <><Square size={10} /> Standby</> : <><Play size={10} /> Activate</>}
                </button>
                <button
                  onClick={() => runAgent(selected.id)}
                  disabled={running === selected.id}
                  className="flex items-center gap-1.5 text-[10px] font-mono uppercase px-3 py-1.5 border border-[#00d4ff]/20 text-[#00d4ff]/60 hover:bg-[#00d4ff]/10 rounded-lg transition-all disabled:opacity-30"
                >
                  <Zap size={10} />{running === selected.id ? 'Scanning...' : 'Scan'}
                </button>
                <button
                  onClick={() => deleteAgent(selected.id)}
                  className="flex items-center gap-1.5 text-[10px] font-mono uppercase px-3 py-1.5 border border-red-500/20 text-red-400/40 hover:bg-red-500/10 hover:text-red-400 rounded-lg transition-all"
                >
                  <Trash2 size={10} />
                </button>
              </div>
            </div>

            {/* Tabs */}
            <div className="flex gap-1 px-6 pt-3 pb-0 border-b border-white/[0.04] flex-shrink-0">
              {(['chat', 'profile'] as const).map(t => (
                <button key={t} onClick={() => setTab(t)}
                  className={`flex items-center gap-1.5 text-[10px] font-mono uppercase px-3 py-2 rounded-t-lg border-b-2 transition-colors ${
                    tab === t
                      ? 'border-[#00d4ff] text-[#00d4ff]/80'
                      : 'border-transparent text-white/25 hover:text-white/50'
                  }`}>
                  {t === 'chat' ? <MessageSquare size={10} /> : <Settings size={10} />}
                  {t}
                </button>
              ))}
            </div>

            {/* Chat tab */}
            {tab === 'chat' && (
              <>
                <div className="flex-1 overflow-y-auto px-6 py-4 space-y-3">
                  {(chatHistory[selected.id] ?? []).length === 0 && (
                    <div className="text-center mt-12 space-y-2">
                      <p className="text-[11px] font-mono text-white/15">Direct comms to {selected.name}</p>
                      <p className="text-[10px] font-mono text-white/10">Give orders, assign tasks, update directives.</p>
                    </div>
                  )}
                  {(chatHistory[selected.id] ?? []).map((m, i) => (
                    <div key={i} className={`flex flex-col gap-0.5 ${m.role === 'user' ? 'items-end' : 'items-start'}`}>
                      <span className="text-[9px] font-mono text-white/20">
                        {m.role === 'user' ? 'DIRECTOR' : selected.name.toUpperCase()}
                      </span>
                      <div className={`max-w-[80%] px-4 py-2.5 rounded-2xl text-sm leading-relaxed ${
                        m.role === 'user'
                          ? 'bg-white/6 border border-white/10 rounded-tr-sm text-white/75'
                          : 'border border-[#00d4ff]/15 bg-[#00d4ff]/5 rounded-tl-sm text-white/80'
                      }`}>
                        {m.content}
                      </div>
                    </div>
                  ))}
                  {chatSending && (
                    <div className="flex items-start gap-2">
                      <div className="border border-[#00d4ff]/15 bg-[#00d4ff]/5 rounded-2xl rounded-tl-sm px-4 py-2.5">
                        <span className="text-[#00d4ff]/40 text-sm">···</span>
                      </div>
                    </div>
                  )}
                  <div ref={chatBottomRef} />
                </div>
                <div className="flex-shrink-0 px-6 pb-5 pt-3 border-t border-white/[0.04]">
                  <div className="flex items-center gap-2 bg-white/4 border border-white/8 rounded-xl px-4 py-2.5 focus-within:border-white/15 transition-colors">
                    <input
                      value={chatInput}
                      onChange={e => setChatInput(e.target.value)}
                      onKeyDown={e => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); sendChat() } }}
                      placeholder={`Order, task, or directive to ${selected.name}...`}
                      disabled={chatSending}
                      className="flex-1 bg-transparent text-sm text-white/80 placeholder:text-white/18 focus:outline-none disabled:opacity-40"
                    />
                    <button onClick={sendChat} disabled={!chatInput.trim() || chatSending}
                      className="w-8 h-8 rounded-xl flex items-center justify-center text-white/30 hover:text-[#00d4ff] hover:bg-[#00d4ff]/10 disabled:opacity-20 disabled:cursor-not-allowed transition-all">
                      <Send size={14} />
                    </button>
                  </div>
                </div>
              </>
            )}

            {/* Profile tab */}
            {tab === 'profile' && (
              <div className="flex-1 overflow-y-auto p-6">
                <div className="max-w-2xl space-y-6">
                  {selected.personality && (
                    <EditableField label="Personality" value={selected.personality} onSave={v => updateField(selected.id, 'personality', v)} />
                  )}
                  {selected.capabilities?.length > 0 && (
                    <div>
                      <p className="text-[10px] font-mono tracking-widest text-white/25 uppercase mb-2">Capabilities</p>
                      <div className="flex flex-wrap gap-2">
                        {selected.capabilities.map((c, i) => (
                          <span key={i} className="text-[11px] font-mono px-2 py-1 bg-white/5 border border-white/8 rounded text-white/50">{c}</span>
                        ))}
                      </div>
                    </div>
                  )}
                  {selected.directives && (
                    <EditableField label="Directives" value={selected.directives} onSave={v => updateField(selected.id, 'directives', v)} />
                  )}
                  {selected.last_scanned_at && (
                    <div>
                      <p className="text-[10px] font-mono tracking-widest text-white/25 uppercase mb-1">Last Scan</p>
                      <p className="text-sm text-white/40">{new Date(selected.last_scanned_at).toLocaleString()}</p>
                    </div>
                  )}
                </div>
              </div>
            )}
          </>
        )}
      </div>

      {/* ── Create Modal ──────────────────────────────────────────────────── */}
      {showCreate && (
        <div className="fixed inset-0 bg-black/70 flex items-center justify-center z-50" onClick={() => setShowCreate(false)}>
          <div className="bg-[#0a0a0a] border border-white/10 rounded-2xl p-8 w-full max-w-lg" onClick={e => e.stopPropagation()}>
            <h2 className="text-[11px] font-mono tracking-[0.3em] text-white/40 uppercase mb-6">Deploy New Agent</h2>

            <div className="space-y-4">
              <div className="flex gap-4">
                <FormField label="Name *">
                  <input autoFocus value={form.name} onChange={e => setForm(f => ({ ...f, name: e.target.value }))}
                    className="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-2.5 text-sm text-white/80 placeholder:text-white/20 focus:outline-none focus:border-white/25"
                    placeholder="Agent name" />
                </FormField>
                <FormField label="Status">
                  <select value={form.status} onChange={e => setForm(f => ({ ...f, status: e.target.value }))}
                    className="w-full bg-white/5 border border-white/10 rounded-xl px-3 py-2.5 text-sm text-white/80 focus:outline-none focus:border-white/25">
                    <option value="standby">standby</option>
                    <option value="active">active</option>
                  </select>
                </FormField>
              </div>
              <FormField label="Role *">
                <input value={form.role} onChange={e => setForm(f => ({ ...f, role: e.target.value }))}
                  className="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-2.5 text-sm text-white/80 placeholder:text-white/20 focus:outline-none focus:border-white/25"
                  placeholder="Intelligence Analyst, Red Team Operator..." />
              </FormField>
              <FormField label="Capabilities (comma-separated)">
                <input value={form.capabilities} onChange={e => setForm(f => ({ ...f, capabilities: e.target.value }))}
                  className="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-2.5 text-sm text-white/80 placeholder:text-white/20 focus:outline-none focus:border-white/25"
                  placeholder="osint, threat modeling, report writing" />
              </FormField>
              <FormField label="Personality">
                <textarea value={form.personality} onChange={e => setForm(f => ({ ...f, personality: e.target.value }))} rows={2}
                  className="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-2.5 text-sm text-white/80 placeholder:text-white/20 focus:outline-none focus:border-white/25 resize-none"
                  placeholder="Agent's personality and operating style..." />
              </FormField>
              <FormField label="Directives">
                <textarea value={form.directives} onChange={e => setForm(f => ({ ...f, directives: e.target.value }))} rows={2}
                  className="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-2.5 text-sm text-white/80 placeholder:text-white/20 focus:outline-none focus:border-white/25 resize-none"
                  placeholder="Operating directives and constraints..." />
              </FormField>
            </div>

            <div className="flex justify-end gap-3 mt-6">
              <button onClick={() => setShowCreate(false)}
                className="px-4 py-2 text-[11px] font-mono uppercase text-white/30 hover:text-white/60 transition-colors">
                Cancel
              </button>
              <button onClick={createAgent} disabled={!form.name.trim() || !form.role.trim() || saving}
                className="px-5 py-2 text-[11px] font-mono uppercase border border-[#00d4ff]/25 text-[#00d4ff]/70 hover:bg-[#00d4ff]/10 rounded-xl transition-all disabled:opacity-30">
                {saving ? 'Deploying...' : 'Deploy Agent'}
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
      {editing
        ? <textarea autoFocus value={draft} onChange={e => setDraft(e.target.value)} rows={3}
            className="w-full bg-white/5 border border-white/15 rounded-xl px-4 py-3 text-sm text-white/80 focus:outline-none focus:border-white/25 resize-none" />
        : <p className="text-sm text-white/55 leading-relaxed whitespace-pre-wrap select-text cursor-text">{value}</p>
      }
    </div>
  )
}
