"use client"

import { useState, useEffect, useRef } from "react"
import { Bot, Plus, X, ChevronRight, ChevronLeft, Zap, Shield, Database, Brain, Activity, Trash2, Edit2, Play, Pause, Loader2, Clock, FileText } from "lucide-react"

type AgentStatus = "active" | "standby" | "offline"

type Agent = {
  id: string
  name: string
  role: string
  personality: string
  capabilities: string[]
  directives: string
  status: AgentStatus
  created_at: string
  updated_at: string
  last_scanned_at: string | null
  total_findings: number
}

type AgentActivityRow = {
  id: string
  action: string
  details: Record<string, any>
  created_at: string
}

const STATUS_COLORS: Record<string, string> = {
  active:   "text-green-400 bg-green-400/10 border-green-400/30",
  standby:  "text-accent bg-accent/10 border-accent/30",
  deployed: "text-green-400 bg-green-400/10 border-green-400/30", // legacy
  offline:  "text-muted-foreground bg-muted border-border",
}

const STATUS_DOT: Record<string, string> = {
  active:   "bg-green-400",
  standby:  "bg-accent",
  deployed: "bg-green-400", // legacy
  offline:  "bg-muted-foreground",
}

const AVATAR_MAP: Record<string, string> = {
  "conversationdiscoverer": "/agents/core_blue.png",
  "guardian of avalon": "/agents/core_gold.png",
  "blitz": "/agents/core_red.png",
  "vesper": "/agents/core_purple.png",
}

function getAgentAvatar(name: string) {
  const key = Object.keys(AVATAR_MAP).find(k => name.toLowerCase().includes(k))
  return key ? AVATAR_MAP[key] : "/agents/core_blue.png"
}

function AgentStatusDropdown({ status, onChange }: { status: string, onChange: (s: AgentStatus) => void }) {
  const [open, setOpen] = useState(false)
  
  useEffect(() => {
    if (!open) return
    const cl = () => setOpen(false)
    // small delay so the open click doesn't trigger this immediately
    setTimeout(() => window.addEventListener("click", cl), 0)
    return () => window.removeEventListener("click", cl)
  }, [open])

  const options = [
    { value: "active", title: "Active", desc: "Runs autonomously in background", dot: "bg-green-400" },
    { value: "standby", title: "Standby", desc: "Paused, requires manual run", dot: "bg-accent" },
    { value: "offline", title: "Offline", desc: "Agent is disabled", dot: "bg-muted-foreground" },
  ]

  return (
    <div className="relative" onClick={(e) => e.stopPropagation()}>
      <button
        onClick={() => setOpen(!open)}
        className={`text-[10px] font-medium border px-2 py-1 rounded uppercase tracking-wider flex items-center gap-1.5 hover:brightness-110 transition-all ${STATUS_COLORS[status] || STATUS_COLORS.offline}`}
      >
        <span className={`w-1.5 h-1.5 rounded-full ${STATUS_DOT[status] || STATUS_DOT.offline}`} />
        {status === "deployed" ? "ACTIVE" : status}
        <ChevronRight size={10} className={`ml-0.5 transition-transform ${open ? "rotate-90" : "rotate-0"}`} />
      </button>

      {open && (
        <div className="absolute top-full left-0 mt-1.5 w-56 bg-card/95 backdrop-blur-md border border-border/80 rounded-xl shadow-2xl z-50 overflow-hidden flex flex-col p-1 animate-in slide-in-from-top-1 fade-in-20 duration-200">
          {options.map(opt => (
            <button
              key={opt.value}
              onClick={() => { onChange(opt.value as AgentStatus); setOpen(false) }}
              className={`flex flex-col items-start px-3 py-2 rounded-lg hover:bg-muted/80 transition-colors text-left ${status === opt.value ? "bg-muted/50" : ""}`}
            >
              <div className="flex items-center gap-1.5">
                <span className={`w-1.5 h-1.5 rounded-full shadow-sm ${opt.dot}`} />
                <span className="text-[11px] font-medium font-semibold text-foreground tracking-wide">{opt.title}</span>
              </div>
              <span className="text-[10px] text-muted-foreground mt-0.5 opacity-80">{opt.desc}</span>
            </button>
          ))}
        </div>
      )}
    </div>
  )
}

const EMPTY_FORM = {
  name: "",
  role: "",
  personality: "",
  capabilities: "",
  directives: "",
  status: "standby" as AgentStatus,
  visibility: "private" as "private" | "shared" | "group" | "public",
}

export default function AgentsPage() {
  const [agents, setAgents] = useState<Agent[]>([])
  const [loading, setLoading] = useState(true)
  const [selected, setSelected] = useState<Agent | null>(null)
  const [showModal, setShowModal] = useState(false)
  const [editing, setEditing] = useState<Agent | null>(null)
  const [form, setForm] = useState(EMPTY_FORM)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [runningAgentId, setRunningAgentId] = useState<string | null>(null)
  const [runResult, setRunResult] = useState<{ findings: number; conversations_scanned: number } | null>(null)
  const [agentActivity, setAgentActivity] = useState<AgentActivityRow[]>([])
  const [activityLoading, setActivityLoading] = useState(false)

  async function loadAgents() {
    setLoading(true)
    const res = await fetch("/api/agents")
    if (res.ok) {
      const data = await res.json()
      setAgents(data)
    }
    setLoading(false)
  }

  useEffect(() => { loadAgents() }, [])

  function openCreate() {
    setEditing(null)
    setForm(EMPTY_FORM)
    setError(null)
    setShowModal(true)
  }

  function openEdit(agent: Agent) {
    setEditing(agent)
    setForm({
      name: agent.name,
      role: agent.role,
      personality: agent.personality,
      capabilities: agent.capabilities.join(", "),
      directives: agent.directives,
      status: agent.status,
      visibility: "private",

    })
    setError(null)
    setShowModal(true)
  }

  async function saveAgent() {
    if (!form.name.trim() || !form.role.trim()) {
      setError("Name and role are required.")
      return
    }
    setSaving(true)
    setError(null)
    const payload = {
      name: form.name.trim(),
      role: form.role.trim(),
      personality: form.personality.trim(),
      capabilities: form.capabilities.split(",").map(c => c.trim()).filter(Boolean),
      directives: form.directives.trim(),
      status: form.status,
    }
    const res = editing
      ? await fetch("/api/agents", { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ id: editing.id, ...payload }) })
      : await fetch("/api/agents", { method: "POST",  headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload) })

    if (res.ok) {
      setShowModal(false)
      setSelected(null)
      await loadAgents()
    } else {
      const d = await res.json()
      setError(d.error ?? "Save failed.")
    }
    setSaving(false)
  }

  async function deleteAgent(id: string) {
    if (!confirm("Remove this agent from Nexus?")) return
    await fetch("/api/agents", { method: "DELETE", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ id }) })
    if (selected?.id === id) setSelected(null)
    await loadAgents()
  }

  async function setStatus(agent: Agent, newStatus: AgentStatus) {
    if (agent.status === newStatus) return
    await fetch("/api/agents", { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ id: agent.id, status: newStatus }) })
    await loadAgents()
    if (selected?.id === agent.id) setSelected(prev => prev ? { ...prev, status: newStatus } : null)
  }

  async function runAgent(agent: Agent, forceFullScan: boolean = false) {
    if (runningAgentId) return
    if (agent.status !== "active") {
      setError("Set agent to Active before running.")
      return
    }
    setRunningAgentId(agent.id)
    setRunResult(null)
    setError(null)
    try {
      const res = await fetch("/api/agents/run", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ agentId: agent.id, forceFullScan }),
      })
      const data = await res.json()
      if (res.ok) {
        setRunResult({ findings: data.findings, conversations_scanned: data.conversations_scanned })
        await loadAgents()
        await loadActivity(agent.id)
      } else {
        setError(data.error || "Run failed")
      }
    } catch (err: any) {
      setError(err.message)
    } finally {
      setRunningAgentId(null)
    }
  }

  async function loadActivity(agentId: string) {
    setActivityLoading(true)
    try {
      const res = await fetch(`/api/agents/run?agentId=${agentId}`)
      if (res.ok) {
        const data = await res.json()
        setAgentActivity(data.activity ?? [])
      }
    } finally {
      setActivityLoading(false)
    }
  }

  // Load activity when selecting an agent
  useEffect(() => {
    if (selected) {
      loadActivity(selected.id)
      setRunResult(null)
    }
  }, [selected?.id])

  return (
    <div className="flex flex-col min-h-screen relative bg-black">
      {selected ? (
        <div className="absolute inset-0 z-50 bg-black flex flex-col">
          <style>{`
            @keyframes slow-spin { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }
            @keyframes reverse-spin { from { transform: rotate(360deg); } to { transform: rotate(0deg); } }
            @keyframes pulse-ring { 0% { transform: scale(0.95); opacity: 0.5; } 50% { transform: scale(1.05); opacity: 0.8; } 100% { transform: scale(0.95); opacity: 0.5; } }
            .animate-slow-spin { animation: slow-spin 12s linear infinite; }
            .animate-reverse-spin { animation: reverse-spin 15s linear infinite; }
            .animate-pulse-ring { animation: pulse-ring 4s ease-in-out infinite; }
          `}</style>
          
          <div className="absolute inset-0 bg-[linear-gradient(rgba(34,211,238,0.02)_1px,transparent_1px),linear-gradient(90deg,rgba(34,211,238,0.02)_1px,transparent_1px)] bg-[size:30px_30px] pointer-events-none" />
          <div className="relative flex flex-col h-full z-10 p-4 md:p-8">
            
            {/* Header Row */}
            <div className="flex items-center justify-between pb-6 border-b border-border">
              <div className="flex items-center gap-6">
                <button onClick={() => setSelected(null)} className="text-muted-foreground hover:text-foreground text-sm font-medium flex items-center gap-2 transition-colors">
                  <ChevronLeft size={16} /> MAP
                </button>
                <div className="h-8 w-px bg-border hidden md:block" />
                <h2 className="font-semibold text-xl md:text-3xl text-foreground font-medium flex items-center gap-3">
                  <div className="w-3 h-3 bg-primary rounded-sm animate-pulse" />
                  {selected.name}
                </h2>
                <div className="hidden md:block">
                  <AgentStatusDropdown status={selected.status} onChange={(s) => setStatus(selected, s)} />
                </div>
              </div>
              
              <div className="flex gap-3">
                 <button onClick={() => runAgent(selected)} disabled={runningAgentId === selected.id || selected.status !== "active"} className="px-4 md:px-6 py-2 rounded-sm bg-muted border border-primary/40 text-foreground font-medium text-[10px] md:text-xs hover:bg-primary/20  disabled:opacity-50 flex items-center transition-all">
                   {runningAgentId === selected.id ? <><Loader2 size={14} className="animate-spin md:mr-2"/> <span className="hidden md:inline">SCANNING...</span></> : <><Play size={14} className="md:mr-2"/> <span className="hidden md:inline">INITIATE SCAN</span></>}
                 </button>
                 <button onClick={() => runAgent(selected, true)} disabled={runningAgentId === selected.id || selected.status !== "active"} className="hidden md:flex px-6 py-2 rounded-sm bg-black border border-amber-900/50 text-amber-500 font-medium text-xs hover:bg-amber-950/30 transition-colors disabled:opacity-40">
                   FULL SCAN
                 </button>
                 <button onClick={() => openEdit(selected)} className="px-3 md:px-4 py-2 rounded-sm bg-black border border-border text-muted-foreground hover:bg-muted hover:text-zinc-200 font-mono transition-colors">
                   <Edit2 size={14} />
                 </button>
                 <button onClick={() => deleteAgent(selected.id)} className="px-3 py-2 rounded-sm border border-red-900/50 text-red-500 hover:bg-red-900/20 transition-colors">
                   <Trash2 size={14} />
                 </button>
              </div>
            </div>

            {/* Main Content Split */}
            <div className="flex-1 flex flex-col md:flex-row overflow-hidden mt-6 gap-6">
              
              {/* Left: Core Visuals & Profile */}
              <div className="w-full md:w-1/2 flex flex-col justify-center items-center relative border border-border bg-muted/5 rounded-xl p-8 overflow-y-auto custom-scrollbar shadow-[inset_0_0_50px_rgba(0,0,0,0.8)]">
                
                {/* Massive Holographic Core */}
                <div className="relative w-44 h-44 sm:w-56 sm:h-56 md:w-80 md:h-80 flex items-center justify-center mb-6 md:mb-10 flex-shrink-0 mix-blend-screen">
                   <svg className="absolute inset-0 w-full h-full text-foreground/30 animate-slow-spin" viewBox="0 0 100 100">
                      <circle cx="50" cy="50" r="48" fill="none" stroke="currentColor" strokeWidth="1" strokeDasharray="4 8" />
                      <circle cx="50" cy="50" r="42" fill="none" stroke="currentColor" strokeWidth="0.5" strokeDasharray="30 10" />
                      <path d="M 50 2 L 50 8 M 50 92 L 50 98 M 2 50 L 8 50 M 92 50 L 98 50" stroke="currentColor" strokeWidth="1.5" />
                   </svg>
                   <svg className="absolute inset-0 w-full h-full text-foreground/40 animate-reverse-spin" viewBox="0 0 100 100">
                      <circle cx="50" cy="50" r="45" fill="none" stroke="currentColor" strokeWidth="2" strokeDasharray="15 45" />
                   </svg>
                   
                   <div className="absolute inset-[15%] rounded-full overflow-hidden border-2 border-primary/40 p-1 bg-black  animate-pulse-ring aspect-square">
                      <img src={getAgentAvatar(selected.name)} className="w-full h-full object-cover rounded-full mix-blend-screen" />
                   </div>
                </div>

                {/* Data modules below the core */}
                <div className="w-full max-w-lg space-y-6 bg-black/40 p-6 rounded-lg border border-border">
                  <div>
                    <h4 className="text-[10px] font-medium text-muted-foreground mb-2 font-semibold flex justify-between">
                      Personality Core <span className="text-muted-foreground">{selected.role}</span>
                    </h4>
                    <p className="text-sm font-light text-foreground leading-relaxed pl-4 border-l-[3px] border-border">{selected.personality}</p>
                  </div>
                  <div>
                    <h4 className="text-[10px] font-medium text-muted-foreground mb-2 font-semibold">Capabilities Configuration</h4>
                    <div className="flex flex-wrap gap-2">
                      {selected.capabilities.map(cap => (
                         <span key={cap} className="text-[10px] bg-muted/40 border border-border text-foreground font-medium px-3 py-1.5 rounded-md">{cap}</span>
                      ))}
                    </div>
                  </div>
                  {selected.directives && (
                    <div>
                      <h4 className="text-[10px] font-medium text-muted-foreground mb-2 font-semibold">Primary Directives</h4>
                      <p className="text-xs text-muted-foreground leading-relaxed font-mono whitespace-pre-wrap pl-4 border-l-[3px] border-border">{selected.directives}</p>
                    </div>
                  )}
                </div>
              </div>

              {/* Right: Massive Terminal Text Log */}
              <div className="w-full md:w-1/2 bg-[#050505] border border-border flex flex-col relative rounded-xl overflow-hidden shadow-2xl">
                 <div className="bg-black border-b border-border px-6 py-5 flex justify-between items-center z-20">
                   <h3 className="font-mono text-foreground font-medium text-xs flex items-center gap-3 font-bold">
                     <span className="w-2 h-2 rounded-full bg-primary animate-pulse" />
                     LIVE TELEMETRY STREAM
                   </h3>
                   <div className="flex gap-4">
                     <span className="font-mono text-[10px] text-muted-foreground hidden xl:inline">LAST SCAN: <span className="text-foreground">{selected.last_scanned_at ? new Date(selected.last_scanned_at).toLocaleDateString() : "NEVER"}</span></span>
                     <span className="font-mono text-[10px] text-muted-foreground hidden sm:inline">FINDINGS: <span className="text-amber-400 font-bold">{selected.total_findings ?? 0}</span></span>
                   </div>
                 </div>

                 <div className="flex-1 overflow-y-auto custom-scrollbar font-mono flex flex-col gap-1.5 p-6 z-10 break-words">
                   {activityLoading ? (
                     <div className="text-muted-foreground p-4 font-bold text-xs animate-pulse">ESTABLISHING SECURE CONNECTION...</div>
                   ) : agentActivity.length === 0 ? (
                     <p className="text-xs text-zinc-600 italic mt-4">{'>>'} NO DATA STREAM AVAILABLE. AWAITING PROCESS INITIALIZATION...</p>
                   ) : (
                     agentActivity.map((a) => (
                       <div key={a.id} className="text-[11px] tracking-wider mb-2 leading-relaxed flex items-start flex-col sm:flex-row hover:bg-muted/30 p-2 rounded transition-colors group">
                         <span className="text-zinc-600 w-28 flex-shrink-0 group-hover:text-muted-foreground">[{new Date(a.created_at).toLocaleTimeString("en-US", { hour12: false })}]</span>
                         
                         <div className="break-words min-w-0 flex-1">
                           {a.action === "scan_started" && <span className="text-foreground font-bold">{'>>'} SCAN_INITIALIZED</span>}
                           {a.action === "scan_completed" && <span className="text-emerald-400 font-bold">{'>>'} SCAN_COMPLETED: <span className="text-emerald-400/80 font-normal">PROCESSED {a.details?.conversations_scanned ?? "ALL"}. NEW INTEL: {a.details?.findings_created ?? 0}</span></span>}
                           {a.action === "finding_created" && <span className="text-amber-400 font-bold">{'>>'} INTEL_EXTRACTED: <span className="text-amber-400/90 font-normal">"{a.details?.title}"</span></span>}
                           {a.action === "batch_completed" && <span className="text-muted-foreground border-l-[2px] border-border pl-3 ml-2">-- BATCH_{a.details?.batch_index}_COMPLETE</span>}
                           {a.action === "error" && <span className="text-red-500 font-bold">{'>>'} SYS_ERROR: <span className="text-red-400 font-normal">{a.details?.error}</span></span>}
                           {/* Default fallback */}
                           {!["scan_started", "scan_completed", "finding_created", "batch_completed", "error"].includes(a.action) && <span className="text-muted-foreground">{'>>'} {a.action.toUpperCase()}</span>}
                         </div>
                       </div>
                     ))
                   )}
                 </div>

                 {/* Terminal Scanline overlay */}
                 <div className="absolute inset-0 pointer-events-none bg-[radial-gradient(circle_at_center,transparent_50%,rgba(0,0,0,0.6)_100%)] z-20" />
                 <div className="absolute inset-0 pointer-events-none opacity-15 bg-[repeating-linear-gradient(rgba(0,0,0,0),rgba(0,0,0,0)_2px,rgba(34,211,238,0.2)_3px,rgba(34,211,238,0.2)_4px)] z-20" />
              </div>

            </div>
          </div>
        </div>
      ) : (
        <div className="flex flex-col flex-1 p-4 md:p-8 max-w-5xl mx-auto w-full">
          <div className="flex items-start md:items-center justify-between gap-3 mb-6 md:mb-8">
            <div className="min-w-0">
              <h1 className="text-2xl md:text-3xl font-bold text-foreground tracking-tight">Agents</h1>
              <p className="text-xs md:text-sm text-foreground/70 mt-1">
                AI personalities tasked with specific operations.
              </p>
            </div>
            <button
              onClick={openCreate}
              className="flex items-center gap-2 bg-muted text-foreground border border-primary/40 px-4 md:px-5 py-2.5 rounded  text-xs font-medium hover:bg-primary/20 transition-colors flex-shrink-0"
            >
              <Plus size={15} />
              <span className="hidden sm:inline">Deploy Agent</span>
              <span className="sm:hidden">Deploy</span>
            </button>
          </div>

          {loading ? (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {[1,2,3].map(i => (
                <div key={i} className="nexus-card p-5 animate-pulse h-40" />
              ))}
            </div>
          ) : agents.length === 0 ? (
            <div className="bg-black/50 border border-border p-16 flex flex-col items-center justify-center text-center rounded-xl">
              <div className="w-12 h-12 rounded-xl bg-muted/40 flex items-center justify-center mb-4 border border-border">
                <Bot size={22} className="text-muted-foreground" />
              </div>
              <h3 className="text-base font-semibold text-foreground font-medium mb-2">No agents deployed</h3>
              <p className="text-sm text-foreground/50 max-w-xs font-mono">
                Agents are AI personalities tasked with data collection, analysis, monitoring, or automation. Deploy one to get started.
              </p>
              <button onClick={openCreate} className="mt-8 text-xs font-medium text-foreground hover:text-foreground transition-colors">Deploy first agent &rarr;</button>
            </div>
          ) : (
            <>
            <style>{`
              @keyframes scanline {
                0% { top: -10%; opacity: 0; }
                10% { opacity: 0.5; }
                90% { opacity: 0.5; }
                100% { top: 110%; opacity: 0; }
              }
              .animate-scanline {
                animation: scanline 4s linear infinite;
              }
              .tech-clip {
                clip-path: polygon(15px 0, 100% 0, 100% calc(100% - 15px), calc(100% - 15px) 100%, 0 100%, 0 15px);
              }
            `}</style>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-8 auto-rows-max">
              {agents.map(agent => (
                <a
                  key={agent.id}
                  href={`/dashboard/agents/${agent.id}`}
                  className={`relative tech-clip border-l-[3px] bg-black/80 backdrop-blur-md p-[1px] cursor-pointer transition-colors duration-200 hover:bg-black/90 group ${
                    agent.status === "active" ? "border-l-primary" :
                    agent.status === "standby" ? "border-l-accent" :
                    "border-l-muted-foreground"
                  }`}
                >
                  {/* Scanline Animation */}
                  {agent.status === "active" && (
                    <div className="absolute left-0 right-0 h-[2px] bg-primary/50  animate-scanline pointer-events-none z-10" />
                  )}
                  
                  {/* Tech Grid Background */}
                  <div className="absolute inset-0 bg-[linear-gradient(rgba(255,255,255,0.02)_1px,transparent_1px),linear-gradient(90deg,rgba(255,255,255,0.02)_1px,transparent_1px)] bg-[size:20px_20px] pointer-events-none" />

                  <div className="relative tech-clip bg-zinc-950/90 h-full p-8 flex flex-col z-0 hover:bg-black transition-colors duration-300">
                    <div className="flex justify-between items-start mb-6 gap-3">
                      <div className="flex gap-5 min-w-0 flex-1">
                        {/* Generative AI Core Avatar */}
                        <div className="w-16 h-16 rounded-full overflow-hidden border-2 border-primary/30 p-0.5 flex items-center justify-center bg-black  aspect-square flex-shrink-0 group-hover: transition-shadow duration-300 relative group-hover:rotate-12">
                          <img src={getAgentAvatar(agent.name)} alt={agent.name} className="w-full h-full object-cover rounded-full mix-blend-screen" />
                        </div>
                        <div className="flex flex-col pt-1 min-w-0 flex-1">
                          <h3 className="font-bold text-xl text-foreground font-medium group-hover:text-foreground transition-colors truncate">{agent.name}</h3>
                          <p className="text-xs text-foreground/80 font-medium mt-1 truncate">{agent.role}</p>
                        </div>
                      </div>
                      <AgentStatusDropdown status={agent.status} onChange={(s) => setStatus(agent, s)} />
                    </div>

                    {agent.personality && (
                      <p className="text-sm text-muted-foreground mb-8 font-light leading-relaxed border-l-[3px] border-border pl-4 mt-2 group-hover:text-foreground group-hover:border-border transition-colors">
                        {agent.personality}
                      </p>
                    )}

                    <div className="flex flex-wrap gap-2 mt-auto">
                      {agent.capabilities.slice(0, 4).map((cap, i) => (
                        <span key={i} className="text-[10px] bg-muted border border-border text-foreground px-3 py-1.5 rounded-sm uppercase group-hover:bg-muted/20 group-hover:border-border transition-colors">
                          {cap}
                        </span>
                      ))}
                      {agent.capabilities.length > 4 && (
                        <span className="text-[10px] bg-muted border border-border text-muted-foreground px-3 py-1.5 rounded-sm uppercase">
                          +{agent.capabilities.length - 4} MORE
                        </span>
                      )}
                    </div>
                  </div>
                </a>
              ))}
            </div>
            </>
          )}
        </div>
      )}

      {/* Create / Edit Modal */}
      {showModal && (
        <div className="fixed inset-0 bg-foreground/50 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="bg-card border border-border rounded-xl w-full max-w-lg shadow-2xl">
            <div className="flex items-center justify-between px-6 py-4 border-b border-border">
              <h2 className="font-semibold text-foreground">{editing ? `Edit ${editing.name}` : "Deploy New Agent"}</h2>
              <button onClick={() => setShowModal(false)} className="text-muted-foreground hover:text-foreground"><X size={16} /></button>
            </div>

            <div className="p-6 flex flex-col gap-4">
              <div className="grid grid-cols-2 gap-4">
                <div className="flex flex-col gap-1.5">
                  <label className="text-sm font-medium text-foreground">Agent Name *</label>
                  <input
                    value={form.name}
                    onChange={e => setForm(f => ({ ...f, name: e.target.value }))}
                    placeholder="e.g. Shade"
                    className="bg-muted border border-border rounded-lg px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:border-accent/50"
                  />
                </div>
                <div className="flex flex-col gap-1.5">
                  <label className="text-sm font-medium text-foreground">Role *</label>
                  <input
                    value={form.role}
                    onChange={e => setForm(f => ({ ...f, role: e.target.value }))}
                    placeholder="e.g. Data Collection"
                    className="bg-muted border border-border rounded-lg px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:border-accent/50"
                  />
                </div>
              </div>

              <div className="flex flex-col gap-1.5">
                <label className="text-sm font-medium text-foreground">Personality</label>
                <textarea
                  value={form.personality}
                  onChange={e => setForm(f => ({ ...f, personality: e.target.value }))}
                  rows={2}
                  placeholder="How this agent communicates and operates..."
                  className="bg-muted border border-border rounded-lg px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:border-accent/50 resize-none"
                />
              </div>

              <div className="flex flex-col gap-1.5">
                <label className="text-sm font-medium text-foreground">Capabilities <span className="normal-case">(comma separated)</span></label>
                <input
                  value={form.capabilities}
                  onChange={e => setForm(f => ({ ...f, capabilities: e.target.value }))}
                  placeholder="e.g. stealth infiltration, predictive modeling, comms interception"
                  className="bg-muted border border-border rounded-lg px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:border-accent/50"
                />
              </div>

              <div className="flex flex-col gap-1.5">
                <label className="text-sm font-medium text-foreground">Directives</label>
                <textarea
                  value={form.directives}
                  onChange={e => setForm(f => ({ ...f, directives: e.target.value }))}
                  rows={3}
                  placeholder="Hard rules this agent follows. What it must always do. What it must never do."
                  className="bg-muted border border-border rounded-lg px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:border-accent/50 resize-none"
                />
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div className="flex flex-col gap-1.5">
                  <label className="text-sm font-medium text-foreground">Status</label>
                  <select
                    value={form.status}
                    onChange={e => setForm(f => ({ ...f, status: e.target.value as AgentStatus }))}
                    className="bg-muted border border-border rounded-lg px-3 py-2 text-sm text-foreground focus:outline-none focus:border-accent/50"
                  >
                    <option value="standby">Standby</option>
                    <option value="active">Active</option>
                    <option value="offline">Offline</option>
                  </select>
                </div>
                <div className="flex flex-col gap-1.5">
                  <label className="text-sm font-medium text-foreground">Visibility</label>
                  <select
                    value={form.visibility}
                    onChange={e => setForm(f => ({ ...f, visibility: e.target.value as any }))}
                    disabled={!!editing}
                    className="bg-muted border border-border rounded-lg px-3 py-2 text-sm text-foreground focus:outline-none focus:border-accent/50 disabled:opacity-50 disabled:cursor-not-allowed"
                    title={editing ? "Visibility can only be set during creation for now" : ""}
                  >
                    <option value="private">Private (Only You)</option>
                    <option value="shared">Shared (Specific Humans)</option>
                    <option value="group">Group</option>
                    <option value="public">Public (All Authenticated Humans)</option>
                  </select>
                </div>
              </div>

              {error && <p className="text-xs text-destructive">{error}</p>}

              <div className="flex gap-3 pt-1">
                <button
                  onClick={() => setShowModal(false)}
                  className="flex-1 text-sm border border-border text-muted-foreground px-4 py-2.5 rounded-lg hover:bg-muted transition-colors"
                >
                  Cancel
                </button>
                <button
                  onClick={saveAgent}
                  disabled={saving}
                  className="flex-1 text-sm bg-accent text-accent-foreground px-4 py-2.5 rounded-lg font-medium hover:bg-accent/80 transition-colors disabled:opacity-50"
                >
                  {saving ? "Saving..." : editing ? "Update Agent" : "Deploy Agent"}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
