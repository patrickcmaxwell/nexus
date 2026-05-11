"use client"

// Per-agent detail. Apple/Linear-style. Tabs for Profile / Findings.
// Status pill is editable (admin); Run-now button kicks the analyzer.

import { useState } from "react"
import { useRouter } from "next/navigation"
import { Play, Pencil, Loader2, Calendar, Target, Sparkles } from "lucide-react"
import { Card, Button, Pill, Section, Tabs, EmptyState } from "@/components/ui/primitives"

type Agent = {
  id: string
  name: string
  role: string
  personality: string | null
  capabilities: string[] | null
  directives: string | null
  status: string
  created_at: string
  last_scanned_at: string | null
  total_findings: number | null
}

type Finding = {
  id: string
  title: string
  description: string
  type: string
  priority: number
  created_at: string
}

const STATUS_TONES: Record<string, "success" | "warning" | "muted"> = {
  active:   "success",
  standby:  "warning",
  offline:  "muted",
  archived: "muted",
}

const AVATAR_MAP: Record<string, string> = {
  conversationdiscoverer: "/agents/core_blue.png",
  "guardian of avalon":   "/agents/core_gold.png",
  blitz:                  "/agents/core_red.png",
  vesper:                 "/agents/core_purple.png",
}

function avatarFor(name: string) {
  const key = Object.keys(AVATAR_MAP).find(k => name.toLowerCase().includes(k))
  return key ? AVATAR_MAP[key] : "/agents/core_blue.png"
}

export default function AgentDetailClient({
  agent, recentFindings,
}: {
  agent: Agent
  recentFindings: Finding[]
}) {
  const router = useRouter()
  const [tab, setTab] = useState("profile")
  const [running, setRunning] = useState(false)
  const [runMsg, setRunMsg] = useState<string | null>(null)

  async function runNow() {
    setRunning(true)
    setRunMsg(null)
    try {
      const res = await fetch("/api/agents/run", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ agentId: agent.id }),
      })
      const data = await res.json().catch(() => ({}))
      if (res.ok) {
        setRunMsg(`Triggered — check findings in a moment.`)
        router.refresh()
      } else {
        setRunMsg(data.error ?? `HTTP ${res.status}`)
      }
    } finally {
      setRunning(false)
    }
  }

  return (
    <>
      {/* Header */}
      <header className="flex items-start gap-5 mb-8">
        <div className="w-20 h-20 rounded-full overflow-hidden border-2 border-primary/30 bg-black flex-shrink-0">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={avatarFor(agent.name)} alt={agent.name} className="w-full h-full object-cover mix-blend-screen" />
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-3 flex-wrap">
            <h1 className="text-2xl font-semibold tracking-tight text-foreground">{agent.name}</h1>
            <Pill tone={STATUS_TONES[agent.status] ?? "muted"}>{agent.status}</Pill>
          </div>
          <p className="text-sm text-muted-foreground mt-2">{agent.role}</p>
          <div className="flex items-center gap-3 mt-3 text-xs text-muted-foreground flex-wrap">
            <span className="flex items-center gap-1.5"><Calendar size={12} /> Created {formatDate(agent.created_at)}</span>
            {agent.last_scanned_at && (
              <span className="flex items-center gap-1.5"><Sparkles size={12} /> Last scan {timeAgo(agent.last_scanned_at)}</span>
            )}
            <span className="flex items-center gap-1.5"><Target size={12} /> {agent.total_findings ?? 0} findings</span>
          </div>
        </div>
        <div className="flex items-center gap-2 flex-shrink-0">
          <Button variant="primary" size="sm" iconLeft={<Play size={13} />} onClick={runNow} loading={running} disabled={agent.status !== "active"}>
            Run now
          </Button>
          <Button variant="secondary" size="sm" iconLeft={<Pencil size={13} />} onClick={() => router.push(`/dashboard/agents?edit=${agent.id}`)}>
            Edit
          </Button>
        </div>
      </header>

      {runMsg && <p className="text-sm text-muted-foreground mb-4">{runMsg}</p>}

      <Tabs
        active={tab}
        onChange={setTab}
        tabs={[
          { id: "profile", label: "Profile" },
          { id: "findings", label: `Findings (${recentFindings.length})` },
        ]}
        className="mb-6"
      />

      {tab === "profile" && (
        <div className="space-y-4">
          {agent.personality && (
            <Card>
              <Section title="Personality">
                <p className="text-sm text-foreground/90 mt-3 leading-relaxed whitespace-pre-wrap">{agent.personality}</p>
              </Section>
            </Card>
          )}

          {agent.capabilities && agent.capabilities.length > 0 && (
            <Card>
              <Section title="Capabilities">
                <div className="flex flex-wrap gap-1.5 mt-3">
                  {agent.capabilities.map(c => (
                    <Pill key={c} tone="muted">{c}</Pill>
                  ))}
                </div>
              </Section>
            </Card>
          )}

          {agent.directives && (
            <Card>
              <Section title="Directives" description="The standing instructions this agent operates under.">
                <p className="text-sm text-foreground/90 mt-3 leading-relaxed whitespace-pre-wrap font-mono bg-muted/30 px-4 py-3 rounded-lg">
                  {agent.directives}
                </p>
              </Section>
            </Card>
          )}
        </div>
      )}

      {tab === "findings" && (
        <Card padding="none">
          {recentFindings.length === 0 ? (
            <EmptyState
              icon={<Target size={28} />}
              title="No findings yet"
              description={agent.status === "active" ? "Hit Run now to kick a scan." : "Activate this agent to start collecting findings."}
            />
          ) : (
            <ul className="divide-y divide-border">
              {recentFindings.map(f => (
                <li key={f.id} className="px-5 py-4 hover:bg-muted/40 transition-colors">
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-2 flex-wrap">
                        <p className="text-sm font-medium text-foreground">{f.title}</p>
                        <Pill tone="muted" size="xs">{f.type}</Pill>
                        {f.priority >= 7 && <Pill tone="warning" size="xs">P{f.priority}</Pill>}
                      </div>
                      {f.description && (
                        <p className="text-sm text-muted-foreground mt-1.5 line-clamp-2">{f.description}</p>
                      )}
                    </div>
                    <span className="text-xs text-muted-foreground flex-shrink-0">{timeAgo(f.created_at)}</span>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </Card>
      )}
    </>
  )
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" })
}
function timeAgo(iso: string): string {
  const ms = Date.now() - new Date(iso).getTime()
  const m = Math.round(ms / 60000)
  if (m < 1) return "just now"
  if (m < 60) return `${m}m ago`
  const h = Math.round(m / 60)
  if (h < 24) return `${h}h ago`
  const d = Math.round(h / 24)
  return `${d}d ago`
}
