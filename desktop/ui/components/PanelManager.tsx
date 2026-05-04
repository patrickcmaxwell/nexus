import React, { useEffect, useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { X } from 'lucide-react'

export type PanelType = 'operations' | 'agent' | 'vault' | 'protocol' | null

interface PanelManagerProps {
  activePanel: PanelType
  onClose: () => void
}

const NEXUS_API = 'http://localhost:3000'

type Operation = { id: string; title: string; status: string; updated_at: string }
type Agent = { id: string; name: string; role: string; status: string; total_findings: number }

export function PanelManager({ activePanel, onClose }: PanelManagerProps) {
  const [operations, setOperations] = useState<Operation[]>([])
  const [agents, setAgents] = useState<Agent[]>([])

  useEffect(() => {
    if (!activePanel) return
    fetch(`${NEXUS_API}/api/desktop/dashboard`)
      .then((r) => r.ok ? r.json() : null)
      .then((data) => {
        if (!data) return
        setOperations(data.operations ?? [])
        setAgents(data.agents ?? [])
      })
      .catch(() => {})
  }, [activePanel])

  return (
    <AnimatePresence>
      {activePanel && (
        <>
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 bg-black/60 backdrop-blur-sm z-40"
            onClick={onClose}
          />

          <motion.div
            initial={{ x: '100%', opacity: 0 }}
            animate={{ x: 0, opacity: 1 }}
            exit={{ x: '100%', opacity: 0 }}
            transition={{ type: 'spring', damping: 25, stiffness: 200 }}
            className="fixed right-0 top-0 bottom-0 w-[500px] bg-card border-l border-border/50 z-50 p-8 shadow-2xl flex flex-col pt-16"
          >
            <button
              onClick={onClose}
              className="absolute top-6 right-6 p-2 rounded-full hover:bg-white/10 transition-colors"
            >
              <X className="w-5 h-5 opacity-60" />
            </button>

            <h2 className="text-2xl font-bold mb-8 uppercase tracking-widest text-primary/80">
              {activePanel}
            </h2>

            <div className="flex-1 overflow-y-auto no-drag">
              {activePanel === 'operations' && <OperationsPanel operations={operations} />}
              {activePanel === 'agent' && <AgentPanel agents={agents} />}
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  )
}

function OperationsPanel({ operations }: { operations: Operation[] }) {
  if (!operations.length) {
    return (
      <div className="text-xs text-white/30 p-4">
        No active operations — start nexus-web to sync.
      </div>
    )
  }
  return (
    <div className="flex flex-col gap-4">
      {operations.map((op) => (
        <div key={op.id} className="p-4 rounded-xl border border-border/50 bg-white/5">
          <div className="flex items-center justify-between mb-1">
            <h3 className="font-bold text-sm text-white">{op.title}</h3>
            <span className="text-xs font-mono text-primary/60 uppercase">{op.status}</span>
          </div>
          <p className="text-xs text-white/30">Updated {timeAgo(op.updated_at)}</p>
        </div>
      ))}
    </div>
  )
}

function AgentPanel({ agents }: { agents: Agent[] }) {
  const eve = agents[0]
  return (
    <div className="flex flex-col gap-4">
      {eve && (
        <div className="p-4 rounded-xl border border-primary/30 bg-primary/10">
          <h3 className="font-bold text-primary">{eve.name}</h3>
          <p className="text-xs text-primary/70 mt-1 pb-3">{eve.role} — {eve.status}</p>
          <div className="grid grid-cols-2 gap-2 text-xs">
            <div className="bg-black/40 p-2 rounded">Findings: {eve.total_findings}</div>
            <div className="bg-black/40 p-2 rounded">Status: {eve.status}</div>
          </div>
        </div>
      )}
      {agents.slice(1).map((agent) => (
        <div key={agent.id} className="p-4 rounded-xl border border-border/50 bg-white/5">
          <h3 className="font-bold text-sm text-white/60">{agent.name}</h3>
          <p className="text-xs text-white/30 mt-1">{agent.role} · {agent.status}</p>
        </div>
      ))}
      {!agents.length && (
        <div className="text-xs text-white/30 p-4">No agents found — start nexus-web to sync.</div>
      )}
    </div>
  )
}

function timeAgo(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime()
  const m = Math.floor(diff / 60000)
  if (m < 1) return 'just now'
  if (m < 60) return `${m}m ago`
  const h = Math.floor(m / 60)
  if (h < 24) return `${h}h ago`
  return `${Math.floor(h / 24)}d ago`
}
