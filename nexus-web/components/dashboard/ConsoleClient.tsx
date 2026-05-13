"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import {
  Activity, Calendar, Database, Settings, Monitor, RefreshCw, Loader2,
  CheckCircle2, AlertTriangle, ArrowRight, LogOut, Trash2,
} from "lucide-react"
import EndpointsHealth, { NEXUS_WEB_ENDPOINTS } from "@/components/dashboard/EndpointsHealth"

// ConsoleClient
//
// nexus-web parallel to Lumen's LumenConsoleWindow. Tabbed surface:
// Today (briefing) / Endpoints (health) / Sessions (active devices) /
// Settings (link out + per-user info).
//
// All client-rendered. The server passes the active human's identity bundle
// in via initialMe; the rest fetches as the user navigates between tabs.

type Initial = {
  humanId: string
  email: string
  displayName: string
  handle: string | null
  role: string
  isOwner: boolean
  authMethod: string | null
  avatarUrl: string | null
}

type Tab = "today" | "endpoints" | "sessions" | "settings"

export default function ConsoleClient({ initial }: { initial: Initial }) {
  const [tab, setTab] = useState<Tab>("today")

  return (
    <div className="min-h-screen p-4 sm:p-6 md:p-10 max-w-4xl mx-auto">
      <header className="mb-8">
        <h1 className="text-2xl font-semibold tracking-tight text-foreground">Console</h1>
        <p className="text-sm text-muted-foreground mt-2">
          Recent changes, endpoint health, sessions, and settings — what&apos;s under the hood.
        </p>
      </header>

      <nav className="flex md:flex-wrap gap-1 mb-6 p-1 rounded-lg bg-muted overflow-x-auto -mx-4 sm:mx-0 px-4 sm:px-1">
        <TabButton label="Today"     active={tab === "today"}     onClick={() => setTab("today")}     icon={Calendar} />
        <TabButton label="Endpoints" active={tab === "endpoints"} onClick={() => setTab("endpoints")} icon={Activity} />
        <TabButton label="Sessions"  active={tab === "sessions"}  onClick={() => setTab("sessions")}  icon={Monitor} />
        <TabButton label="Settings"  active={tab === "settings"}  onClick={() => setTab("settings")}  icon={Settings} />
      </nav>

      <section>
        {tab === "today"     && <TodayTab />}
        {tab === "endpoints" && <EndpointsTab />}
        {tab === "sessions"  && <SessionsTab />}
        {tab === "settings"  && <SettingsTab initial={initial} />}
      </section>
    </div>
  )
}

// MARK: - Tab button

function TabButton({
  label, active, onClick, icon: Icon,
}: {
  label: string; active: boolean; onClick: () => void; icon: typeof Activity
}) {
  return (
    <button
      onClick={onClick}
      className={`flex items-center gap-2 px-3 py-1.5 text-sm font-medium rounded-md transition-colors whitespace-nowrap flex-shrink-0 ${
        active
          ? "bg-card text-foreground shadow-sm"
          : "text-muted-foreground hover:text-foreground"
      }`}
    >
      <Icon size={14} />
      {label}
    </button>
  )
}

// MARK: - Today tab

type Briefing = {
  stats: { activeOps: number; activeAgents: number; activeDirectives: number; memories: number }
  delta: {
    newOperations: Array<{ id: string; label: string; status: string; createdAt?: string }>
    statusChangedOperations: Array<{ id: string; label: string; status: string; updatedAt?: string }>
    newRecords: Array<{ id: string; title: string; type: string; operationLabel?: string; createdAt?: string }>
    completedResearch: Array<{ id: string; operationLabel: string; summary: string; completedAt?: string }>
    findings: { totalCount: number; latest: Array<{ agent: string; summary: string; createdAt?: string }> }
  }
}

function TodayTab() {
  const [data, setData] = useState<Briefing | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    setLoading(true); setError(null)
    try {
      const res = await fetch("/api/eve/briefing", { credentials: "include" })
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const json = await res.json()
      setData(json as Briefing)
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load briefing")
    } finally {
      setLoading(false)
    }
  }
  useEffect(() => { load() }, [])

  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between">
        <p className="text-sm font-medium text-foreground">
          What&apos;s moved since 24h ago
        </p>
        <button
          onClick={load}
          disabled={loading}
          className="px-3 py-1.5 text-xs font-medium rounded-md text-muted-foreground hover:text-foreground hover:bg-muted disabled:opacity-40 transition-colors flex items-center gap-1.5"
          style={{
            color: "inherit",
            background: "transparent",
            border: "none",
          }}
        >
          {loading ? <Loader2 size={12} className="animate-spin" /> : <RefreshCw size={12} />}
          Refresh
        </button>
      </div>

      {error && (
        <ErrorBox text={error} />
      )}

      {data && (
        <>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
            <StatTile label="Active ops"   value={data.stats.activeOps}        color="var(--nexus-cyan)" />
            <StatTile label="Active agents" value={data.stats.activeAgents}    color="oklch(0.65 0.22 290)" />
            <StatTile label="Directives"   value={data.stats.activeDirectives} color="oklch(0.78 0.18 350)" />
            <StatTile label="Memories"     value={data.stats.memories}         color="oklch(0.78 0.18 155)" />
          </div>

          {data.delta.newOperations.length > 0 && (
            <Section title={`New operations · ${data.delta.newOperations.length}`}>
              {data.delta.newOperations.map((op) => (
                <SimpleRow key={op.id} primary={op.label} secondary={op.status.toUpperCase()} time={op.createdAt} />
              ))}
            </Section>
          )}

          {data.delta.statusChangedOperations.length > 0 && (
            <Section title={`Status changes · ${data.delta.statusChangedOperations.length}`}>
              {data.delta.statusChangedOperations.map((op) => (
                <SimpleRow key={op.id} primary={op.label} secondary={op.status.toUpperCase()} time={op.updatedAt} />
              ))}
            </Section>
          )}

          {data.delta.newRecords.length > 0 && (
            <Section title={`New records · ${data.delta.newRecords.length}`}>
              {data.delta.newRecords.map((r) => (
                <SimpleRow key={r.id} primary={r.title} secondary={`${r.type.toUpperCase()}${r.operationLabel ? ` · ${r.operationLabel}` : ""}`} time={r.createdAt} />
              ))}
            </Section>
          )}

          {data.delta.completedResearch.length > 0 && (
            <Section title={`Research completed · ${data.delta.completedResearch.length}`}>
              {data.delta.completedResearch.map((r) => (
                <div key={r.id} className="px-3 py-2.5 bg-white/[0.025] flex flex-col gap-1">
                  <div className="flex items-center justify-between">
                    <p className="text-sm text-white/85 font-semibold">{r.operationLabel}</p>
                    {r.completedAt && (
                      <span className="font-mono text-[9px] tracking-widest text-white/40">{relativeTime(r.completedAt)}</span>
                    )}
                  </div>
                  {r.summary && <p className="text-[11px] text-white/55 line-clamp-3">{r.summary}</p>}
                </div>
              ))}
            </Section>
          )}

          {data.delta.findings.latest.length > 0 && (
            <Section title={`Agent findings · ${data.delta.findings.totalCount}`}>
              {data.delta.findings.latest.map((f, i) => (
                <SimpleRow key={i} primary={f.summary} secondary={`by ${f.agent}`} time={f.createdAt} />
              ))}
            </Section>
          )}

          {isQuiet(data.delta) && (
            <p className="text-sm text-white/45 mt-2">Nothing new in the last 24 hours.</p>
          )}
        </>
      )}
    </div>
  )
}

// MARK: - Endpoints tab

function EndpointsTab() {
  return <EndpointsHealth endpoints={NEXUS_WEB_ENDPOINTS} title="API Reachability" />
}

// MARK: - Sessions tab

type Session = {
  id: string
  created_at: string
  last_verified_at: string
  expires_at: string
  auth_method: string
  current: boolean
}

function SessionsTab() {
  const [sessions, setSessions] = useState<Session[]>([])
  const [loading, setLoading] = useState(true)
  const [revoking, setRevoking] = useState<string | null>(null)

  async function load() {
    setLoading(true)
    try {
      const res = await fetch("/api/auth/sessions", { credentials: "include" })
      if (res.ok) {
        const data = await res.json()
        setSessions(data.sessions ?? [])
      }
    } finally {
      setLoading(false)
    }
  }
  useEffect(() => { load() }, [])

  async function revoke(id: string) {
    if (!confirm("Revoke this session?")) return
    setRevoking(id)
    try {
      const res = await fetch(`/api/auth/sessions/${id}`, { method: "DELETE" })
      if (res.ok) {
        const sess = sessions.find((s) => s.id === id)
        if (sess?.current) { window.location.replace("/"); return }
        load()
      }
    } finally {
      setRevoking(null)
    }
  }

  async function signOutOthers() {
    if (!confirm("Sign out every other device? Your current session stays.")) return
    setRevoking("others")
    try {
      const res = await fetch("/api/auth/sessions", {
        method: "DELETE",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ scope: "others" }),
      })
      if (res.ok) load()
    } finally {
      setRevoking(null)
    }
  }

  return (
    <div className="space-y-4">
      <p className="font-mono text-[10px] tracking-[0.25em] uppercase" style={{ color: "var(--nexus-cyan)" }}>
        Active sessions
      </p>
      <p className="text-xs text-muted-foreground">
        Devices currently signed in to your account. Revoke any you don't recognize.
      </p>

      {loading ? (
        <Loader2 size={16} className="animate-spin text-muted-foreground" />
      ) : sessions.length === 0 ? (
        <p className="text-xs text-muted-foreground">No active sessions found.</p>
      ) : (
        <div className="flex flex-col gap-2">
          {sessions.map((s) => (
            <div
              key={s.id}
              className={`flex items-center justify-between gap-3 px-4 py-3 rounded-lg border ${
                s.current
                  ? "bg-primary/5 border-primary/40"
                  : "bg-transparent border-border"
              }`}
            >
              <div className="flex flex-col min-w-0 gap-0.5">
                <div className="flex items-center gap-2 flex-wrap">
                  <span className={`text-sm font-medium ${s.current ? "text-primary" : "text-foreground"}`}>
                    {s.auth_method}
                  </span>
                  {s.current && (
                    <span className="text-xs px-2 py-0.5 rounded-md bg-primary/15 text-primary">
                      This device
                    </span>
                  )}
                </div>
                <span className="text-xs text-muted-foreground">
                  Last active {relativeTime(s.last_verified_at)} · expires {new Date(s.expires_at).toLocaleDateString()}
                </span>
              </div>
              <button
                onClick={() => revoke(s.id)}
                disabled={revoking === s.id}
                className="px-3 py-1.5 text-xs font-medium text-muted-foreground hover:text-destructive border border-border hover:border-destructive/50 hover:bg-destructive/10 rounded-lg disabled:opacity-40 transition-colors flex items-center gap-1.5"
              >
                {revoking === s.id ? <Loader2 size={11} className="animate-spin" /> : <Trash2 size={11} />}
                Revoke
              </button>
            </div>
          ))}
        </div>
      )}

      <button
        onClick={signOutOthers}
        disabled={revoking === "others" || sessions.filter((s) => !s.current).length === 0}
        className="px-4 py-2 text-sm font-medium rounded-lg text-destructive border border-destructive/40 hover:bg-destructive/10 transition-colors flex items-center gap-2 disabled:opacity-40"
      >
        <LogOut size={14} /> Sign out other devices
      </button>
    </div>
  )
}

// MARK: - Settings tab

function SettingsTab({ initial }: { initial: Initial }) {
  const router = useRouter()
  return (
    <div className="space-y-5">
      <p className="text-sm font-medium text-foreground">You</p>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
        <Field label="Display name" value={initial.displayName} />
        <Field label="Email"        value={initial.email} />
        <Field label="Handle"       value={initial.handle ?? "—"} />
        <Field label="Role"         value={`${initial.role}${initial.isOwner ? " (owner)" : ""}`} />
        <Field label="Auth method"  value={initial.authMethod ?? "—"} />
      </div>

      <button
        onClick={() => router.push("/dashboard/settings")}
        className="self-start px-4 py-2 text-sm font-medium rounded-lg bg-primary text-primary-foreground hover:opacity-90 transition-opacity flex items-center gap-2"
      >
        Edit profile, change PIN, manage avatar <ArrowRight size={14} />
      </button>
    </div>
  )
}

// MARK: - Visual primitives

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-2">
      <p className="text-sm font-medium text-foreground">{title}</p>
      <div className="flex flex-col gap-1">{children}</div>
    </div>
  )
}

function SimpleRow({ primary, secondary, time }: { primary: string; secondary?: string; time?: string }) {
  return (
    <div className="flex items-center gap-3 px-4 py-2.5 rounded-lg bg-muted/40">
      <div className="flex-1 min-w-0">
        <p className="text-sm text-foreground truncate">{primary}</p>
        {secondary && <p className="text-xs text-muted-foreground truncate">{secondary}</p>}
      </div>
      {time && (
        <span className="text-xs text-muted-foreground">{relativeTime(time)}</span>
      )}
    </div>
  )
}

function StatTile({ label, value, color }: { label: string; value: number; color: string }) {
  return (
    <div className="p-4 rounded-lg bg-card border border-border">
      <p className="text-2xl font-semibold tabular-nums" style={{ color }}>{value}</p>
      <p className="text-xs text-muted-foreground mt-1">{label}</p>
    </div>
  )
}

function Field({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex flex-col gap-1 px-4 py-3 rounded-lg bg-muted/40">
      <p className="text-xs text-muted-foreground">{label}</p>
      <p className="text-sm text-foreground truncate">{value}</p>
    </div>
  )
}

function ErrorBox({ text }: { text: string }) {
  return (
    <div className="flex items-center gap-2 px-3 py-2.5 rounded-lg bg-destructive/10 border border-destructive/30">
      <AlertTriangle size={14} className="text-destructive" />
      <p className="text-sm text-destructive">{text}</p>
    </div>
  )
}

function isQuiet(d: Briefing["delta"]): boolean {
  return d.newOperations.length === 0 &&
         d.statusChangedOperations.length === 0 &&
         d.newRecords.length === 0 &&
         d.completedResearch.length === 0 &&
         d.findings.latest.length === 0
}

function relativeTime(iso: string): string {
  const ms = Date.now() - new Date(iso).getTime()
  const m = Math.round(ms / 60000)
  if (m < 1) return "just now"
  if (m < 60) return `${m}m ago`
  const h = Math.round(m / 60)
  if (h < 24) return `${h}h ago`
  const d = Math.round(h / 24)
  return `${d}d ago`
}
