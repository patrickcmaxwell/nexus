"use client"

import { useState } from "react"
import Link from "next/link"
import { Plus } from "lucide-react"

type Agent = {
  id: string
  name: string
  role: string
  status: string | null
  capabilities: string[] | null
  personality: string | null
  directives: string | null
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

const STATUS_COLOR: Record<string, string> = {
  active:   "text-green-400 border-green-400/30",
  standby:  "text-yellow-400 border-yellow-400/30",
  offline:  "text-muted-foreground border-border",
  archived: "text-muted-foreground border-border",
}

function statusLabel(s: string | null): string {
  return (s || "STANDBY").toUpperCase()
}

function statusColor(s: string | null): string {
  return STATUS_COLOR[(s || "standby").toLowerCase()] || STATUS_COLOR.standby
}

export default function SuitsClient({ agents }: { agents: Agent[] }) {
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const selected = agents.find(a => a.id === selectedId) ?? null

  const activeCount  = agents.filter(a => (a.status || "").toLowerCase() === "active").length
  const standbyCount = agents.filter(a => (a.status || "").toLowerCase() === "standby" || !a.status).length
  const offlineCount = agents.filter(a => ["offline", "archived"].includes((a.status || "").toLowerCase())).length

  return (
    <div className="p-4 md:p-8 scan-line min-h-screen">
      <div className="mb-6 md:mb-8 flex items-start justify-between gap-3">
        <div>
          <p className="font-mono text-xs text-muted-foreground mb-1" style={{ fontFamily: "var(--font-orbitron)" }}>{">"} ARMOR DIVISION</p>
          <h1 className="text-xl md:text-2xl font-bold text-hud-gold tracking-widest" style={{ fontFamily: "var(--font-orbitron)" }}>SUIT REGISTRY</h1>
          <p className="font-mono text-xs text-muted-foreground mt-1">
            {activeCount} active · {standbyCount} standby · {offlineCount} offline
          </p>
        </div>
        <Link
          href="/dashboard/agents"
          className="hud-border hud-glow-gold px-3 md:px-5 py-2 md:py-2.5 font-mono text-[10px] md:text-xs text-hud-gold hover:bg-[oklch(0.75_0.18_75/0.15)] transition-all flex items-center gap-1.5 flex-shrink-0"
          style={{ fontFamily: "var(--font-orbitron)" }}
        >
          <Plus size={12} /> NEW SUIT
        </Link>
      </div>

      {agents.length === 0 ? (
        <div className="hud-border bg-card p-10 text-center">
          <p className="font-mono text-sm text-muted-foreground mb-2" style={{ fontFamily: "var(--font-orbitron)" }}>NO SUITS DEPLOYED</p>
          <p className="font-mono text-xs text-muted-foreground/70 leading-relaxed mb-6 max-w-md mx-auto">
            Suits are agent personas Eve can wear — writer, analyst, on-call, friend. Build your first one from the Agents bay.
          </p>
          <Link
            href="/dashboard/agents"
            className="hud-border hud-glow-gold inline-flex px-6 py-2.5 font-mono text-xs text-hud-gold hover:bg-[oklch(0.75_0.18_75/0.15)] transition-all items-center gap-2"
            style={{ fontFamily: "var(--font-orbitron)" }}
          >
            <Plus size={14} /> BUILD A SUIT
          </Link>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3 md:gap-4">
          {agents.map((agent) => {
            const isSelected = selected?.id === agent.id
            return (
              <button
                key={agent.id}
                onClick={() => setSelectedId(isSelected ? null : agent.id)}
                className="hud-border bg-card p-4 md:p-5 text-left cursor-pointer hover:border-[oklch(0.55_0.22_25/0.7)] transition-all"
              >
                <div className="flex items-start gap-3 md:gap-4 mb-3">
                  {/* Suit avatar — matches /dashboard/agents palette */}
                  <div className="w-12 h-12 md:w-14 md:h-14 rounded-full overflow-hidden border-2 border-[oklch(0.75_0.18_75/0.4)] bg-black flex-shrink-0">
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src={getAgentAvatar(agent.name)} alt={agent.name} className="w-full h-full object-cover mix-blend-screen" />
                  </div>
                  <div className="min-w-0 flex-1">
                    <h2 className="font-bold text-foreground truncate" style={{ fontFamily: "var(--font-orbitron)" }}>{agent.name}</h2>
                    <p className="font-mono text-[10px] text-muted-foreground uppercase tracking-widest truncate">{agent.role || "operative"}</p>
                  </div>
                  <span className={`font-mono text-[10px] border px-2 py-0.5 flex-shrink-0 ${statusColor(agent.status)}`} style={{ fontFamily: "var(--font-orbitron)" }}>
                    {statusLabel(agent.status)}
                  </span>
                </div>

                {(agent.capabilities && agent.capabilities.length > 0) && (
                  <div className="flex flex-wrap gap-1.5 mb-2">
                    {agent.capabilities.slice(0, isSelected ? 99 : 4).map((cap) => (
                      <span key={cap} className="font-mono text-[10px] hud-border px-2 py-0.5 text-muted-foreground">{cap}</span>
                    ))}
                    {!isSelected && agent.capabilities.length > 4 && (
                      <span className="font-mono text-[10px] text-muted-foreground/60 px-1">+{agent.capabilities.length - 4}</span>
                    )}
                  </div>
                )}

                {isSelected && (
                  <div className="border-t border-border pt-3 mt-3 space-y-3">
                    {agent.personality && (
                      <div>
                        <p className="font-mono text-[10px] text-hud-gold mb-1" style={{ fontFamily: "var(--font-orbitron)" }}>PERSONALITY CORE</p>
                        <p className="text-xs text-muted-foreground leading-relaxed">{agent.personality}</p>
                      </div>
                    )}
                    {agent.directives && (
                      <div>
                        <p className="font-mono text-[10px] text-hud-gold mb-1" style={{ fontFamily: "var(--font-orbitron)" }}>PRIMARY DIRECTIVES</p>
                        <p className="font-mono text-xs text-muted-foreground leading-relaxed whitespace-pre-wrap">{agent.directives}</p>
                      </div>
                    )}
                    <Link
                      href="/dashboard/agents"
                      className="font-mono text-[10px] text-accent hover:text-accent/80 inline-flex items-center gap-1"
                      style={{ fontFamily: "var(--font-orbitron)" }}
                    >
                      EDIT IN AGENTS BAY →
                    </Link>
                  </div>
                )}
              </button>
            )
          })}
        </div>
      )}
    </div>
  )
}
