"use client"

import { useEffect, useState } from "react"
import {
  Activity, AlertCircle, ArrowUpRight, CheckCircle2, ExternalLink,
  Filter, Loader2, RefreshCw, Sparkles,
} from "lucide-react"
import EndpointsHealth, { type EndpointDef } from "@/components/dashboard/EndpointsHealth"

// ArenaPanel
//
// Full Arena surface inside nexus-web. Counterpart to arena-web's dashboard
// for read-side work — see audit log + connections without leaving nexus.
// Connection management (add / edit / delete) still happens in arena-web
// because that's where the add/edit forms live; we link out to it.

type Action = {
  id: string
  action: string
  caller: string | null
  payload: Record<string, unknown> | null
  result: Record<string, unknown> | null
  status: string
  error_msg: string | null
  created_at: string
}

type Connection = {
  id: string
  provider: string
  label: string | null
  status: string
  last_used_at: string | null
  last_error: string | null
  created_at: string
}

const ARENA_ENDPOINTS: EndpointDef[] = [
  { id: "arena-health",  group: "Arena", method: "GET",  path: "/api/health",      purpose: "Service alive + provider list" },
  { id: "arena-task-c",  group: "Arena", method: "POST", path: "/api/task/create", purpose: "Eve creates tasks" },
  { id: "arena-task-u",  group: "Arena", method: "POST", path: "/api/task/update", purpose: "Eve updates task status" },
  { id: "arena-pay",     group: "Arena", method: "POST", path: "/api/payment/route", purpose: "Eve routes split payments" },
  { id: "arena-conn",    group: "Arena", method: "GET",  path: "/api/connections", purpose: "Your connections (cookie-auth)" },
]

const ARENA_BASE = "https://arena-web-green.vercel.app"

export default function ArenaPanel({
  initialActions, initialConnections,
}: {
  initialActions: Action[]
  initialConnections: Connection[]
}) {
  const [actions, setActions] = useState<Action[]>(initialActions)
  const [connections] = useState<Connection[]>(initialConnections)
  const [filter, setFilter] = useState<string>("all")
  const [callerFilter, setCallerFilter] = useState<string>("all")
  const [refreshing, setRefreshing] = useState(false)

  async function refresh() {
    setRefreshing(true)
    try {
      const res = await fetch("/api/arena/log?limit=60", { credentials: "include" })
      if (res.ok) {
        const data = await res.json()
        setActions(data.entries ?? [])
      }
    } finally {
      setRefreshing(false)
    }
  }

  // Filter visible actions
  const visible = actions.filter((a) => {
    if (filter !== "all" && !a.action.startsWith(filter)) return false
    if (callerFilter !== "all" && a.caller !== callerFilter) return false
    return true
  })

  // Stats
  const successCount = actions.filter((a) => a.status === "success").length
  const errorCount = actions.filter((a) => a.status === "error").length
  const mockedCount = actions.filter((a) => (a.result as any)?.mocked === true).length

  // Connection summary by provider
  const connByProvider: Record<string, number> = {}
  for (const c of connections) {
    connByProvider[c.provider] = (connByProvider[c.provider] ?? 0) + 1
  }

  // Errored-connection list drives the warning banner at the top of the
  // page. Sourced from connection.status which the executor flips to
  // "errored" when a real call hits an auth error.
  const erroredConnections = connections.filter((c) => c.status === "errored")

  return (
    <main className="min-h-screen p-6 md:p-10 max-w-5xl mx-auto">
      <header className="mb-8 flex items-start justify-between">
        <div>
          <p className="font-mono text-[10px] tracking-[0.3em] uppercase mb-1" style={{ color: "var(--nexus-cyan)" }}>
            Arena
          </p>
          <h1 className="text-2xl font-bold text-foreground">The executor layer</h1>
          <p className="text-sm text-muted-foreground mt-1">
            What Eve actually did in the real world. Connect ClickUp, Notion, GitHub, Stripe to give her hands.
          </p>
        </div>
        <a
          href={`${ARENA_BASE}/dashboard`}
          target="_blank"
          rel="noreferrer"
          className="px-4 py-2 font-mono text-[10px] tracking-[0.2em] uppercase flex items-center gap-2"
          style={{
            color: "var(--nexus-cyan)",
            background: "oklch(0.75 0.18 200 / 0.12)",
            border: "1px solid oklch(0.75 0.18 200 / 0.5)",
          }}
        >
          <ExternalLink size={12} /> Manage Connections
        </a>
      </header>

      {/* Errored-connection banner — surfaces stale credentials before
          the next silent failure. The auto-recheck layer in arena-web sets
          status='errored' on connections whose last call hit auth errors. */}
      {erroredConnections.length > 0 && (
        <div
          className="mb-6 p-4 flex items-start justify-between gap-4"
          style={{
            background: "oklch(0.65 0.22 25 / 0.08)",
            border: "1px solid oklch(0.65 0.22 25 / 0.45)",
          }}
        >
          <div className="flex gap-3 items-start">
            <AlertCircle size={18} className="text-red-400 mt-0.5 shrink-0" />
            <div>
              <p className="font-mono text-[10px] tracking-[0.25em] uppercase text-red-400 mb-1">
                {erroredConnections.length} connection{erroredConnections.length === 1 ? "" : "s"} need attention
              </p>
              <p className="text-sm text-white/80">
                Eve&apos;s last calls to these providers failed with auth errors. Most likely a rotated or revoked token.
              </p>
              <p className="text-xs text-white/55 mt-2">
                {erroredConnections
                  .map((c) => `${c.provider}${c.label ? ` · ${c.label}` : ""}`)
                  .join("  ·  ")}
              </p>
            </div>
          </div>
          <a
            href={`${ARENA_BASE}/dashboard`}
            target="_blank"
            rel="noreferrer"
            className="px-3 py-2 font-mono text-[10px] tracking-[0.2em] uppercase flex items-center gap-2 shrink-0"
            style={{
              color: "rgb(252,165,165)",
              background: "oklch(0.65 0.22 25 / 0.18)",
              border: "1px solid oklch(0.65 0.22 25 / 0.6)",
            }}
          >
            Open Arena Web <ExternalLink size={12} />
          </a>
        </div>
      )}

      {/* Stats grid */}
      <section className="grid grid-cols-2 md:grid-cols-4 gap-2 md:gap-3 mb-8">
        <StatTile label="Total actions" value={actions.length} color="var(--nexus-cyan)" icon={Activity} />
        <StatTile label="Successful"    value={successCount}  color="oklch(0.78 0.18 155)" icon={CheckCircle2} />
        <StatTile label="Errored"       value={errorCount}    color="oklch(0.65 0.22 25)"  icon={AlertCircle} />
        <StatTile label="Mocked"        value={mockedCount}   color="oklch(0.85 0.16 90)"  icon={Sparkles} />
      </section>

      {/* Connections summary */}
      <section className="mb-8">
        <div className="flex items-center justify-between mb-3">
          <h2 className="font-mono text-[10px] tracking-[0.25em] uppercase" style={{ color: "var(--nexus-cyan)" }}>
            Your Connections
          </h2>
          <a
            href={`${ARENA_BASE}/dashboard`}
            target="_blank"
            rel="noreferrer"
            className="font-mono text-[9px] tracking-widest uppercase text-muted-foreground hover:text-foreground flex items-center gap-1"
          >
            Add or edit <ArrowUpRight size={10} />
          </a>
        </div>
        {connections.length === 0 ? (
          <p className="text-sm text-muted-foreground p-4 bg-white/[0.025] border border-white/5">
            No connections yet. Eve&apos;s arena calls will run in safe-mock mode until you add at least one.
            Connect ClickUp, Notion, GitHub, or Stripe at{" "}
            <a href={`${ARENA_BASE}/dashboard`} target="_blank" rel="noreferrer" className="underline">arena-web</a>.
          </p>
        ) : (
          <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
            {Object.entries(connByProvider).map(([prov, count]) => (
              <ProviderCard key={prov} provider={prov} count={count} connections={connections.filter((c) => c.provider === prov)} />
            ))}
          </div>
        )}
      </section>

      {/* Endpoint health */}
      <section className="mb-8">
        <h2 className="font-mono text-[10px] tracking-[0.25em] uppercase mb-3" style={{ color: "var(--nexus-cyan)" }}>
          Service Health
        </h2>
        <EndpointsHealth endpoints={ARENA_ENDPOINTS} baseUrl={ARENA_BASE} />
      </section>

      {/* Action log */}
      <section>
        <div className="flex items-center justify-between mb-3">
          <h2 className="font-mono text-[10px] tracking-[0.25em] uppercase" style={{ color: "var(--nexus-cyan)" }}>
            Action Log
          </h2>
          <button
            onClick={refresh}
            disabled={refreshing}
            className="px-3 py-1.5 font-mono text-[9px] tracking-widest uppercase flex items-center gap-1.5 disabled:opacity-40"
            style={{
              color: "var(--nexus-cyan)",
              background: "oklch(0.75 0.18 200 / 0.1)",
              border: "1px solid oklch(0.75 0.18 200 / 0.4)",
            }}
          >
            {refreshing ? <Loader2 size={10} className="animate-spin" /> : <RefreshCw size={10} />}
            Refresh
          </button>
        </div>

        {/* Filters */}
        <div className="flex flex-wrap gap-2 mb-3">
          <FilterGroup
            label="Action"
            value={filter}
            options={[
              { key: "all",     label: "All" },
              { key: "task",    label: "Tasks" },
              { key: "payment", label: "Payments" },
              { key: "sync",    label: "Sync" },
            ]}
            onChange={setFilter}
          />
          <FilterGroup
            label="Caller"
            value={callerFilter}
            options={[
              { key: "all",    label: "All" },
              { key: "eve",    label: "Eve" },
              { key: "lumen",  label: "Lumen" },
              { key: "manual", label: "Manual" },
            ]}
            onChange={setCallerFilter}
          />
        </div>

        {visible.length === 0 ? (
          <p className="text-sm text-muted-foreground p-4 bg-white/[0.025] border border-white/5">
            No actions match these filters.
          </p>
        ) : (
          <ul className="flex flex-col gap-1">
            {visible.map((a) => (
              <ActionRow key={a.id} action={a} />
            ))}
          </ul>
        )}
      </section>
    </main>
  )
}

// MARK: - Components

function StatTile({
  label, value, color, icon: Icon,
}: {
  label: string; value: number; color: string; icon: typeof Activity
}) {
  return (
    <div className="p-3" style={{ background: `${color} / 0.06`, border: `1px solid ${color}33` }}>
      <div className="flex items-center justify-between mb-1">
        <Icon size={12} style={{ color }} />
        <p className="font-mono text-2xl font-bold tabular-nums" style={{ color }}>{value}</p>
      </div>
      <p className="font-mono text-[9px] tracking-widest uppercase text-white/45">{label}</p>
    </div>
  )
}

function ProviderCard({
  provider, count, connections,
}: {
  provider: string; count: number; connections: Connection[]
}) {
  const accent = providerAccent(provider)
  const errored = connections.filter((c) => c.status === "errored").length
  return (
    <div className="p-3" style={{ background: `${accent} / 0.06`, border: `1px solid ${accent}33` }}>
      <div className="flex items-center justify-between mb-1">
        <p className="font-mono text-[10px] tracking-[0.2em] uppercase" style={{ color: accent }}>
          {provider}
        </p>
        <p className="font-mono text-sm tabular-nums" style={{ color: accent }}>×{count}</p>
      </div>
      <p className="text-[10px] text-white/45">
        {errored > 0 ? <span className="text-red-400">{errored} errored</span> : "All healthy"}
      </p>
    </div>
  )
}

function FilterGroup({
  label, value, options, onChange,
}: {
  label: string
  value: string
  options: Array<{ key: string; label: string }>
  onChange: (v: string) => void
}) {
  return (
    <div className="flex items-center gap-1 p-1 bg-white/[0.04] border border-white/8">
      <Filter size={10} className="text-white/35 mx-1" />
      <span className="font-mono text-[8px] tracking-widest uppercase text-white/35 mr-1">{label}</span>
      {options.map((opt) => (
        <button
          key={opt.key}
          onClick={() => onChange(opt.key)}
          className="font-mono text-[9px] tracking-[0.15em] uppercase px-2 py-1"
          style={{
            color: value === opt.key ? "var(--nexus-cyan)" : "rgba(255,255,255,0.5)",
            background: value === opt.key ? "oklch(0.75 0.18 200 / 0.12)" : "transparent",
            border: value === opt.key ? "1px solid oklch(0.75 0.18 200 / 0.4)" : "1px solid transparent",
          }}
        >
          {opt.label}
        </button>
      ))}
    </div>
  )
}

function ActionRow({ action }: { action: Action }) {
  const mocked = (action.result as any)?.mocked === true
  const detail = (action.result as any)?.detail as string | undefined
  return (
    <li className="flex items-center gap-3 px-3 py-2.5 bg-white/[0.025]">
      {action.status === "success" ? (
        <CheckCircle2 size={14} className="text-emerald-400 shrink-0" />
      ) : (
        <AlertCircle size={14} className="text-red-400 shrink-0" />
      )}
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <span className="font-mono text-xs uppercase tracking-widest text-white/85">{action.action}</span>
          {action.caller && (
            <span className="font-mono text-[9px] tracking-widest uppercase text-white/40">via {action.caller}</span>
          )}
          {mocked && (
            <span
              className="font-mono text-[9px] tracking-widest uppercase px-1.5 py-0.5 inline-flex items-center gap-1"
              style={{ color: "rgb(252,211,77)", background: "rgba(252,211,77,0.1)", border: "1px solid rgba(252,211,77,0.4)" }}
            >
              <Sparkles size={9} /> mocked
            </span>
          )}
        </div>
        {action.error_msg && (
          <p className="text-[11px] text-red-400/80 mt-0.5 line-clamp-2">{action.error_msg}</p>
        )}
        {!action.error_msg && detail && (
          <p className="text-[11px] text-white/45 mt-0.5 truncate">{detail}</p>
        )}
      </div>
      <span className="font-mono text-[9px] tracking-widest text-white/40 shrink-0">
        {relative(action.created_at)}
      </span>
    </li>
  )
}

function providerAccent(provider: string): string {
  switch (provider) {
    case "clickup": return "oklch(0.78 0.18 265)"
    case "notion":  return "oklch(0.92 0.02 240)"
    case "github":  return "oklch(0.85 0.005 0)"
    case "stripe":  return "oklch(0.65 0.22 270)"
    default:        return "oklch(0.6 0 0)"
  }
}

function relative(iso: string): string {
  const ms = Date.now() - new Date(iso).getTime()
  const m = Math.round(ms / 60000)
  if (m < 1) return "just now"
  if (m < 60) return `${m}m ago`
  const h = Math.round(m / 60)
  if (h < 24) return `${h}h ago`
  const d = Math.round(h / 24)
  return `${d}d ago`
}
