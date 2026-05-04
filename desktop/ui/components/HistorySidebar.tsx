import React, { useEffect, useState } from 'react'
import { motion } from 'framer-motion'
import { X, MessageSquare, Plus, Trash2 } from 'lucide-react'

const NEXUS_API = 'http://localhost:3000'

interface Convo { id: string; title: string; created_at: string; updated_at?: string }
interface Message { role: string; content: string; ts?: string; created_at?: string }

interface Props {
  sessionId: string
  onClose: () => void
  onNew: () => void
  onLoad: (messages: Message[], convId: string) => void
}

export function HistorySidebar({ sessionId, onClose, onNew, onLoad }: Props) {
  const [convos, setConvos]   = useState<Convo[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    fetch(`${NEXUS_API}/api/eve/conversations`, {
      headers: { Authorization: `Bearer ${sessionId}` },
    })
      .then(r => r.ok ? r.json() : null)
      .then(d => { if (d) setConvos(d.conversations ?? []) })
      .catch(() => {})
      .finally(() => setLoading(false))
  }, [sessionId])

  async function loadConvo(c: Convo) {
    const res = await fetch(`${NEXUS_API}/api/eve/history?conversationId=${c.id}`, {
      headers: { Authorization: `Bearer ${sessionId}` },
    })
    if (!res.ok) return
    const data = await res.json()
    onLoad(data.messages ?? [], c.id)
  }

  async function deleteConvo(id: string, e: React.MouseEvent) {
    e.stopPropagation()
    if (!confirm('Delete this conversation?')) return
    await fetch(`${NEXUS_API}/api/eve/conversations`, {
      method: 'DELETE',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${sessionId}` },
      body: JSON.stringify({ id }),
    })
    setConvos(prev => prev.filter(c => c.id !== id))
  }

  function relativeTime(iso: string) {
    const diff = Date.now() - new Date(iso).getTime()
    const m = Math.floor(diff / 60000)
    if (m < 1)  return 'just now'
    if (m < 60) return `${m}m ago`
    const h = Math.floor(m / 60)
    if (h < 24) return `${h}h ago`
    return `${Math.floor(h / 24)}d ago`
  }

  return (
    <motion.div
      initial={{ x: '-100%' }}
      animate={{ x: 0 }}
      exit={{ x: '-100%' }}
      transition={{ type: 'spring', damping: 28, stiffness: 220 }}
      className="w-64 bg-[#060606] border-r border-white/5 flex flex-col flex-shrink-0 overflow-hidden"
    >
      <div className="flex items-center justify-between px-4 py-3 border-b border-white/5">
        <span className="text-[10px] font-mono tracking-[0.3em] text-white/30 uppercase">Sessions</span>
        <button onClick={onClose} className="text-white/20 hover:text-white/50 transition-colors">
          <X size={14} />
        </button>
      </div>

      <button
        onClick={onNew}
        className="mx-3 mt-3 mb-1 flex items-center gap-2 text-[11px] font-mono text-[#00d4ff]/50 hover:text-[#00d4ff] border border-[#00d4ff]/10 hover:border-[#00d4ff]/30 px-3 py-2 rounded-lg transition-colors"
      >
        <Plus size={11} /> New Session
      </button>

      <div className="flex-1 overflow-y-auto no-scrollbar py-1">
        {loading && (
          <p className="text-[10px] font-mono text-white/20 text-center py-6 animate-pulse">Loading...</p>
        )}
        {!loading && !convos.length && (
          <p className="text-[10px] font-mono text-white/20 text-center py-8">No sessions yet</p>
        )}
        {convos.map(c => (
          <button
            key={c.id}
            onClick={() => loadConvo(c)}
            className="w-full text-left px-4 py-2.5 hover:bg-white/4 transition-colors group flex items-start gap-2"
          >
            <MessageSquare size={11} className="text-white/15 group-hover:text-[#00d4ff]/40 mt-0.5 flex-shrink-0" />
            <div className="flex-1 min-w-0">
              <p className="text-[11px] text-white/40 group-hover:text-white/70 truncate leading-tight">{c.title}</p>
              <p className="text-[9px] font-mono text-white/15 mt-0.5">{relativeTime(c.updated_at ?? c.created_at)}</p>
            </div>
            <button
              onClick={e => deleteConvo(c.id, e)}
              className="opacity-0 group-hover:opacity-100 text-white/20 hover:text-red-400 transition-all flex-shrink-0 mt-0.5"
            >
              <Trash2 size={10} />
            </button>
          </button>
        ))}
      </div>
    </motion.div>
  )
}
