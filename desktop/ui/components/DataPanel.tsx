import React, { useEffect, useState, useCallback } from 'react'
import { motion } from 'framer-motion'
import { X, Zap, Users, Target, RefreshCw, ChevronRight, Circle, Plus } from 'lucide-react'

const NEXUS_API = 'http://localhost:3000'

type Tab = 'ops' | 'agents' | 'directives'

interface Operation {
  id: string; title: string; codename: string; status: string; priority: string
  updated_at: string; operation_records: { count: number }[]
}
interface Agent {
  id: string; name: string; role: string; status: string; total_findings: number; last_scanned_at: string | null
}
interface Directive {
  id: string; type: string; title: string; content: string; priority: number; target: string; active: boolean
}

const STATUS_COLOR: Record<string, string> = {
  active: '#00ff88', standby: '#ffb800', offline: '#ffffff33',
  in_progress: '#00d4ff', complete: '#00ff88', failed: '#ff4444',
  paused: '#ffb800', planning: '#a78bfa',
}

function statusColor(s: string) { return STATUS_COLOR[s?.toLowerCase()] ?? '#ffffff33' }

interface Props { sessionId: string; onClose: () => void }

export function DataPanel({ sessionId, onClose }: Props) {
  const [tab, setTab]             = useState<Tab>('ops')
  const [ops, setOps]             = useState<Operation[]>([])
  const [agents, setAgents]       = useState<Agent[]>([])
  const [directives, setDirectives] = useState<Directive[]>([])
  const [loading, setLoading]     = useState(false)
  const [newDirective, setNewDirective] = useState(false)
  const [dForm, setDForm]         = useState({ title: '', content: '', type: 'directive' })

  const h = { Authorization: `Bearer ${sessionId}` }

  const load = useCallback(async (t: Tab) => {
    setLoading(true)
    try {
      if (t === 'ops') {
        const r = await fetch(`${NEXUS_API}/api/operations`, { headers: h })
        if (r.ok) { const d = await r.json(); setOps(d.operations ?? []) }
      } else if (t === 'agents') {
        const r = await fetch(`${NEXUS_API}/api/agents`, { headers: h })
        if (r.ok) { const d = await r.json(); setAgents(d.agents ?? []) }
      } else {
        const r = await fetch(`${NEXUS_API}/api/eve/directives`, { headers: h })
        if (r.ok) { const d = await r.json(); setDirectives(d.directives ?? []) }
      }
    } catch {}
    setLoading(false)
  }, [sessionId])

  useEffect(() => { load(tab) }, [tab, load])

  async function createDirective() {
    if (!dForm.title || !dForm.content) return
    const r = await fetch(`${NEXUS_API}/api/eve/directives`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...h },
      body: JSON.stringify({ ...dForm, priority: 0, target: 'all' }),
    })
    if (r.ok) { setNewDirective(false); setDForm({ title: '', content: '', type: 'directive' }); load('directives') }
  }

  async function runAgent(id: string) {
    await fetch(`${NEXUS_API}/api/agents/run`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...h },
      body: JSON.stringify({ agent_id: id }),
    })
    setTimeout(() => load('agents'), 2000)
  }

  function relTime(iso: string | null) {
    if (!iso) return 'never'
    const m = Math.floor((Date.now() - new Date(iso).getTime()) / 60000)
    if (m < 1)  return 'just now'
    if (m < 60) return `${m}m ago`
    const h = Math.floor(m / 60)
    if (h < 24) return `${h}h ago`
    return `${Math.floor(h / 24)}d ago`
  }

  return (
    <motion.div
      initial={{ x: '100%' }}
      animate={{ x: 0 }}
      exit={{ x: '100%' }}
      transition={{ type: 'spring', damping: 28, stiffness: 220 }}
      className="w-80 bg-[#060606] border-l border-white/5 flex flex-col flex-shrink-0 overflow-hidden"
    >
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-white/5">
        <div className="flex gap-0 text-[10px] font-mono">
          {(['ops', 'agents', 'directives'] as Tab[]).map(t => (
            <button
              key={t}
              onClick={() => setTab(t)}
              className={`px-2.5 py-1 uppercase tracking-widest transition-colors rounded ${
                tab === t ? 'text-[#00d4ff] bg-[#00d4ff]/10' : 'text-white/25 hover:text-white/50'
              }`}
            >
              {t === 'ops' ? 'OPS' : t === 'agents' ? 'AGTS' : 'DIR'}
            </button>
          ))}
        </div>
        <div className="flex items-center gap-2">
          <button onClick={() => load(tab)} className="text-white/20 hover:text-white/50 transition-colors">
            <RefreshCw size={12} className={loading ? 'animate-spin' : ''} />
          </button>
          <button onClick={onClose} className="text-white/20 hover:text-white/50 transition-colors">
            <X size={14} />
          </button>
        </div>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto no-scrollbar py-2">

        {/* Operations */}
        {tab === 'ops' && (
          <div className="space-y-1 px-2">
            {loading && <p className="text-[10px] font-mono text-white/20 text-center py-6 animate-pulse">Loading...</p>}
            {!loading && !ops.length && <p className="text-[10px] font-mono text-white/20 text-center py-8">No operations</p>}
            {ops.map(op => (
              <div key={op.id} className="p-3 rounded-xl border border-white/5 hover:border-white/10 bg-white/2 hover:bg-white/4 transition-all group">
                <div className="flex items-start justify-between gap-2 mb-1.5">
                  <div className="flex-1 min-w-0">
                    <p className="text-[10px] font-mono tracking-widest uppercase" style={{ color: statusColor(op.status) }}>{op.codename}</p>
                    <p className="text-xs text-white/70 mt-0.5 leading-tight">{op.title}</p>
                  </div>
                  <div className="flex items-center gap-1 flex-shrink-0">
                    <Circle size={6} style={{ fill: statusColor(op.status), color: statusColor(op.status) }} />
                  </div>
                </div>
                <div className="flex items-center gap-3 text-[9px] font-mono text-white/25">
                  <span>{op.status}</span>
                  <span>{op.priority} priority</span>
                  <span>{relTime(op.updated_at)}</span>
                </div>
                {op.operation_records?.[0]?.count > 0 && (
                  <p className="text-[9px] font-mono text-white/20 mt-1">{op.operation_records[0].count} records</p>
                )}
              </div>
            ))}
          </div>
        )}

        {/* Agents */}
        {tab === 'agents' && (
          <div className="space-y-1 px-2">
            {loading && <p className="text-[10px] font-mono text-white/20 text-center py-6 animate-pulse">Loading...</p>}
            {!loading && !agents.length && <p className="text-[10px] font-mono text-white/20 text-center py-8">No agents</p>}
            {agents.map(ag => (
              <div key={ag.id} className="p-3 rounded-xl border border-white/5 hover:border-white/10 bg-white/2 hover:bg-white/4 transition-all group">
                <div className="flex items-start justify-between mb-1.5">
                  <div>
                    <div className="flex items-center gap-1.5">
                      <Circle size={5} style={{ fill: statusColor(ag.status), color: statusColor(ag.status) }} />
                      <p className="text-xs font-semibold text-white/80">{ag.name}</p>
                    </div>
                    <p className="text-[10px] text-white/35 mt-0.5 leading-tight">{ag.role}</p>
                  </div>
                  <button
                    onClick={() => runAgent(ag.id)}
                    className="opacity-0 group-hover:opacity-100 text-[9px] font-mono text-[#00d4ff]/60 hover:text-[#00d4ff] border border-[#00d4ff]/20 hover:border-[#00d4ff]/50 px-2 py-0.5 rounded transition-all"
                  >
                    RUN
                  </button>
                </div>
                <div className="flex items-center gap-3 text-[9px] font-mono text-white/25">
                  <span>{ag.status}</span>
                  {ag.total_findings > 0 && <span>{ag.total_findings} findings</span>}
                  <span>scanned {relTime(ag.last_scanned_at)}</span>
                </div>
              </div>
            ))}
          </div>
        )}

        {/* Directives */}
        {tab === 'directives' && (
          <div className="space-y-1 px-2">
            <button
              onClick={() => setNewDirective(v => !v)}
              className="w-full flex items-center gap-2 text-[10px] font-mono text-[#00d4ff]/50 hover:text-[#00d4ff] border border-[#00d4ff]/10 hover:border-[#00d4ff]/30 px-3 py-2 rounded-lg transition-colors mb-2"
            >
              <Plus size={10} /> New Directive
            </button>

            {newDirective && (
              <div className="p-3 border border-white/10 rounded-xl bg-white/3 space-y-2 mb-2">
                <input
                  value={dForm.title}
                  onChange={e => setDForm(f => ({ ...f, title: e.target.value }))}
                  placeholder="Title..."
                  className="w-full bg-white/5 border border-white/10 rounded px-2 py-1.5 text-xs text-white placeholder:text-white/20 focus:outline-none focus:border-[#00d4ff]/30"
                />
                <textarea
                  value={dForm.content}
                  onChange={e => setDForm(f => ({ ...f, content: e.target.value }))}
                  placeholder="Content..."
                  rows={3}
                  className="w-full bg-white/5 border border-white/10 rounded px-2 py-1.5 text-xs text-white placeholder:text-white/20 focus:outline-none focus:border-[#00d4ff]/30 resize-none"
                />
                <button
                  onClick={createDirective}
                  className="w-full text-[10px] font-mono bg-[#00d4ff]/15 text-[#00d4ff] hover:bg-[#00d4ff]/25 py-1.5 rounded transition-colors"
                >
                  SAVE
                </button>
              </div>
            )}

            {loading && <p className="text-[10px] font-mono text-white/20 text-center py-6 animate-pulse">Loading...</p>}
            {!loading && !directives.length && <p className="text-[10px] font-mono text-white/20 text-center py-8">No directives</p>}
            {directives.map(d => (
              <div key={d.id} className={`p-3 rounded-xl border ${d.active ? 'border-[#00d4ff]/15 bg-[#00d4ff]/4' : 'border-white/5 bg-white/2'} hover:border-white/15 transition-all`}>
                <div className="flex items-start gap-2">
                  <ChevronRight size={10} className="mt-0.5 flex-shrink-0" style={{ color: d.active ? '#00d4ff' : '#ffffff33' }} />
                  <div className="min-w-0">
                    <p className="text-[10px] font-mono tracking-widest uppercase text-white/30 mb-0.5">{d.type}</p>
                    <p className="text-xs text-white/70 leading-tight">{d.title}</p>
                    <p className="text-[10px] text-white/30 mt-1 leading-snug line-clamp-2">{d.content}</p>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </motion.div>
  )
}
