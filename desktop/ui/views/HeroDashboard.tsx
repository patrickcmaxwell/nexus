import React, { useEffect, useState } from 'react'

const NEXUS_API = 'http://localhost:3000'

type Directive = { id: string; directive: string; created_at: string }
type Agent = { id: string; name: string; role: string; status: string; last_scanned_at: string | null; total_findings: number }

export function HeroDashboard() {
  const [directives, setDirectives] = useState<Directive[]>([])
  const [agents, setAgents] = useState<Agent[]>([])

  useEffect(() => {
    let cancelled = false
    let retryTimer: ReturnType<typeof setTimeout> | null = null

    function load(delay = 0) {
      retryTimer = setTimeout(() => {
        fetch(`${NEXUS_API}/api/desktop/dashboard`)
          .then((r) => r.ok ? r.json() : null)
          .then((data) => {
            if (cancelled) return
            if (!data) { retryTimer = setTimeout(() => load(), 10_000); return }
            setDirectives(data.directives ?? [])
            setAgents(data.agents ?? [])
          })
          .catch(() => { if (!cancelled) retryTimer = setTimeout(() => load(), 10_000) })
      }, delay)
    }

    load()
    return () => { cancelled = true; if (retryTimer) clearTimeout(retryTimer) }
  }, [])

  return (
    <div className="w-full max-w-5xl mx-auto flex gap-8 items-start relative z-10 px-8">
      {/* Left Column: Directives */}
      <div className="flex-1 space-y-6">
        <h2 className="text-xs font-bold tracking-widest text-primary/50 uppercase">Active Directives</h2>
        <div className="space-y-3">
          {directives.length > 0 ? directives.slice(0, 4).map((d) => (
            <DirectiveCard key={d.id} title={d.directive} time={timeAgo(d.created_at)} active={true} />
          )) : (
            <>
              <DirectiveCard title="No directives loaded" time="—" active={false} />
              <p className="text-xs text-white/20 px-1">Start nexus-web to sync</p>
            </>
          )}
        </div>
      </div>

      {/* Right Column: Agents */}
      <div className="w-80 space-y-6">
        <h2 className="text-xs font-bold tracking-widest text-primary/50 uppercase">Active Core</h2>
        <div className="space-y-3">
          {agents.length > 0 ? agents.map((agent, i) => (
            <AgentCard key={agent.id} agent={agent} primary={i === 0} />
          )) : (
            <div className="p-5 border border-primary/40 bg-primary/10 rounded-2xl relative overflow-hidden group">
              <div className="absolute top-0 right-0 w-32 h-32 bg-primary/20 rounded-full blur-3xl -mr-10 -mt-10" />
              <h3 className="font-bold text-lg text-white">Eve</h3>
              <p className="text-xs text-primary/70 mt-1">Lumen System Protector</p>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

function AgentCard({ agent, primary }: { agent: Agent; primary: boolean }) {
  const isActive = agent.status === 'active'
  return (
    <div className={`p-5 border rounded-2xl relative overflow-hidden group ${primary ? 'border-primary/40 bg-primary/10' : 'border-border bg-card'}`}>
      {primary && <div className="absolute top-0 right-0 w-32 h-32 bg-primary/20 rounded-full blur-3xl -mr-10 -mt-10 group-hover:bg-primary/30 transition-all" />}
      <h3 className={`font-bold text-lg ${primary ? 'text-white' : 'text-white/60'}`}>{agent.name}</h3>
      <p className={`text-xs mt-1 ${primary ? 'text-primary/70' : 'text-white/30'}`}>{agent.role}</p>
      {agent.total_findings > 0 && (
        <p className="text-xs text-white/40 mt-2">{agent.total_findings} findings</p>
      )}
      <div className={`inline-block mt-2 text-xs px-2 py-0.5 rounded-full ${isActive ? 'bg-primary/20 text-primary' : 'bg-white/10 text-white/30'}`}>
        {agent.status}
      </div>
    </div>
  )
}

function DirectiveCard({ title, time, active }: { title: string; time: string; active: boolean }) {
  return (
    <div className={`p-4 rounded-xl border flex items-center justify-between ${active ? 'border-primary/50 bg-primary/5' : 'border-border/50 bg-white/5'}`}>
      <span className={`text-sm ${active ? 'text-white' : 'text-white/60'}`}>{title}</span>
      <span className="text-xs font-mono text-white/40 ml-4 shrink-0">{time}</span>
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
