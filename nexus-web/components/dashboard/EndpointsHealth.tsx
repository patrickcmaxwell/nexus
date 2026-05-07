"use client"

import { useState } from "react"
import { Activity, Loader2, Radio } from "lucide-react"

// EndpointsHealth
//
// nexus-web mirror of Lumen's EndpointsView. Lists every API route the
// dashboard depends on, lets the user "Ping" each individually or all at
// once, surfaces last status code + latency. Reusable — Phase 2 (Arena)
// uses it scoped to the Arena routes.
//
// Probes are unauthenticated GETs; we treat any HTTP response (including
// 401) as "reachable." Auth errors don't mean the server is down.

export type EndpointDef = {
  id: string         // unique key (also serves as path)
  group: string      // visual grouping
  method: "GET" | "POST" | "PATCH" | "DELETE"
  path: string
  purpose: string
}

type HealthResult = {
  status: "ok" | "warn" | "down" | "unknown"
  httpCode: number | null
  latencyMs: number
  checkedAt: number
  detail: string | null
}

type Props = {
  endpoints: EndpointDef[]
  /** Override the host (defaults to relative URL, i.e. same origin). */
  baseUrl?: string
  /** Optional title rendered above the list. */
  title?: string
}

export default function EndpointsHealth({ endpoints, baseUrl = "", title }: Props) {
  const [health, setHealth] = useState<Record<string, HealthResult>>({})
  const [pinging, setPinging] = useState<Set<string>>(new Set())

  async function ping(endpoint: EndpointDef) {
    if (endpoint.method !== "GET") {
      // POST/PATCH/DELETE we don't probe — we'd need to know what to send.
      setHealth((h) => ({
        ...h,
        [endpoint.id]: {
          status: "unknown",
          httpCode: null,
          latencyMs: 0,
          checkedAt: Date.now(),
          detail: `Probe not implemented for ${endpoint.method}`,
        },
      }))
      return
    }
    setPinging((p) => new Set(p).add(endpoint.id))
    const started = Date.now()
    try {
      const res = await fetch(`${baseUrl}${endpoint.path}`, { method: "GET", credentials: "include" })
      const latency = Date.now() - started
      const code = res.status
      const status: HealthResult["status"] =
        code >= 200 && code < 300 ? "ok"
          : code >= 400 && code < 500 ? "warn"
          : "down"
      setHealth((h) => ({
        ...h,
        [endpoint.id]: { status, httpCode: code, latencyMs: latency, checkedAt: Date.now(), detail: null },
      }))
    } catch (err) {
      const latency = Date.now() - started
      setHealth((h) => ({
        ...h,
        [endpoint.id]: {
          status: "down",
          httpCode: null,
          latencyMs: latency,
          checkedAt: Date.now(),
          detail: err instanceof Error ? err.message : "fetch failed",
        },
      }))
    } finally {
      setPinging((p) => {
        const next = new Set(p)
        next.delete(endpoint.id)
        return next
      })
    }
  }

  function pingAll() {
    for (const e of endpoints) {
      if (e.method === "GET") ping(e)
    }
  }

  // Group endpoints by `group` for the UI, preserving discovery order.
  const groupOrder = Array.from(new Set(endpoints.map((e) => e.group)))
  const grouped: Record<string, EndpointDef[]> = {}
  for (const e of endpoints) {
    grouped[e.group] = grouped[e.group] || []
    grouped[e.group].push(e)
  }

  // Health summary pill
  const known = Object.values(health)
  let summary: { label: string; color: string } | null = null
  if (known.length > 0) {
    const healthy = known.filter((h) => h.status === "ok").length
    if (healthy === known.length) summary = { label: `ALL ${known.length} HEALTHY`, color: "oklch(0.78 0.18 155)" }
    else if (healthy === 0)       summary = { label: `ALL ${known.length} DOWN`,    color: "oklch(0.65 0.22 25)" }
    else                          summary = { label: `${healthy}/${known.length} HEALTHY`, color: "oklch(0.85 0.16 90)" }
  }

  return (
    <div className="flex flex-col gap-5">
      {title && (
        <div className="flex items-center gap-2">
          <Radio size={14} style={{ color: "var(--nexus-cyan)" }} />
          <h3 className="font-mono text-[11px] tracking-[0.25em] uppercase" style={{ color: "var(--nexus-cyan)" }}>
            {title}
          </h3>
        </div>
      )}

      <div className="flex items-center gap-3">
        <button
          onClick={pingAll}
          disabled={pinging.size > 0}
          className="px-3 py-2 font-mono text-[10px] tracking-[0.2em] uppercase flex items-center gap-2 disabled:opacity-40"
          style={{
            background: "oklch(0.75 0.18 200 / 0.12)",
            border: "1px solid oklch(0.75 0.18 200 / 0.5)",
            color: "var(--nexus-cyan)",
          }}
        >
          <Activity size={12} />
          Ping All
        </button>
        {summary && (
          <span
            className="font-mono text-[9px] tracking-widest px-2 py-1 uppercase"
            style={{
              background: `${summary.color} / 0.1`,
              color: summary.color,
              border: `1px solid ${summary.color}55`,
            }}
          >
            {summary.label}
          </span>
        )}
      </div>

      {groupOrder.map((groupName) => (
        <div key={groupName} className="flex flex-col gap-1">
          <p className="font-mono text-[9px] tracking-[0.25em] uppercase text-muted-foreground/60">
            {groupName}
          </p>
          <div className="flex flex-col">
            {grouped[groupName].map((endpoint) => (
              <EndpointRow
                key={endpoint.id}
                endpoint={endpoint}
                health={health[endpoint.id]}
                isPinging={pinging.has(endpoint.id)}
                onPing={() => ping(endpoint)}
              />
            ))}
          </div>
        </div>
      ))}
    </div>
  )
}

function EndpointRow({
  endpoint, health, isPinging, onPing,
}: {
  endpoint: EndpointDef
  health: HealthResult | undefined
  isPinging: boolean
  onPing: () => void
}) {
  const methodColor = methodColorFor(endpoint.method)
  return (
    <div className="flex items-center gap-3 px-3 py-2.5 bg-white/[0.025]">
      <span
        className="font-mono text-[9px] font-bold tracking-widest px-1.5 py-0.5 text-center"
        style={{
          color: methodColor,
          background: `${methodColor} / 0.12`,
          border: `1px solid ${methodColor}55`,
          width: 50,
        }}
      >
        {endpoint.method}
      </span>
      <div className="flex-1 min-w-0">
        <p className="font-mono text-xs text-white/85 truncate">{endpoint.path}</p>
        <p className="text-[10px] text-white/45 truncate">{endpoint.purpose}</p>
      </div>
      {health ? (
        <div className="flex items-center gap-2 min-w-[120px] justify-end">
          <span
            className="rounded-full"
            style={{ width: 6, height: 6, background: statusColor(health.status), boxShadow: `0 0 6px ${statusColor(health.status)}88` }}
          />
          {health.httpCode !== null ? (
            <span className="font-mono text-[10px] font-bold" style={{ color: statusColor(health.status) }}>
              {health.httpCode}
            </span>
          ) : (
            <span className="font-mono text-[10px] text-white/40">—</span>
          )}
          <span className="font-mono text-[9px] text-white/45 min-w-[50px] text-right">
            {health.latencyMs > 0 ? `${health.latencyMs}MS` : ""}
          </span>
        </div>
      ) : (
        <span className="font-mono text-[9px] tracking-widest text-white/30 min-w-[80px] text-right">UNTESTED</span>
      )}
      <button
        onClick={onPing}
        disabled={isPinging}
        className="font-mono text-[9px] tracking-widest px-2 py-1 disabled:opacity-40"
        style={{
          color: "var(--nexus-cyan)",
          background: "oklch(0.75 0.18 200 / 0.1)",
          border: "1px solid oklch(0.75 0.18 200 / 0.4)",
          width: 50,
        }}
      >
        {isPinging ? <Loader2 size={10} className="animate-spin mx-auto" /> : "PING"}
      </button>
    </div>
  )
}

function methodColorFor(m: string): string {
  switch (m) {
    case "GET":    return "oklch(0.78 0.18 155)"
    case "POST":   return "oklch(0.85 0.16 90)"
    case "PATCH":  return "oklch(0.65 0.22 290)"
    case "DELETE": return "oklch(0.65 0.22 25)"
    default:       return "oklch(0.6 0 0)"
  }
}

function statusColor(s: HealthResult["status"]): string {
  switch (s) {
    case "ok":      return "oklch(0.78 0.18 155)"
    case "warn":    return "oklch(0.85 0.16 90)"
    case "down":    return "oklch(0.65 0.22 25)"
    case "unknown": return "oklch(0.6 0 0)"
  }
}

// Default endpoint catalog used by the Console "Endpoints" tab.
export const NEXUS_WEB_ENDPOINTS: EndpointDef[] = [
  { id: "/api/auth/me",            group: "Auth",       method: "GET", path: "/api/auth/me",            purpose: "Current human profile + role" },
  { id: "/api/auth/known-users",   group: "Auth",       method: "GET", path: "/api/auth/known-users",   purpose: "Team picker source" },
  { id: "/api/auth/sessions",      group: "Auth",       method: "GET", path: "/api/auth/sessions",      purpose: "Active sessions for current human" },
  { id: "/api/eve/conversations",  group: "Eve",        method: "GET", path: "/api/eve/conversations",  purpose: "Conversation list w/ previews" },
  { id: "/api/eve/directives",     group: "Eve",        method: "GET", path: "/api/eve/directives",     purpose: "User-defined directives" },
  { id: "/api/eve/memory",         group: "Eve",        method: "GET", path: "/api/eve/memory",         purpose: "Memory bank" },
  { id: "/api/eve/briefing",       group: "Eve",        method: "GET", path: "/api/eve/briefing",       purpose: "What changed since last visit" },
  { id: "/api/operations",         group: "Operations", method: "GET", path: "/api/operations",         purpose: "Operations + nested records/agents" },
  { id: "/api/operations/records", group: "Operations", method: "GET", path: "/api/operations/records", purpose: "Record CRUD" },
  { id: "/api/agents",             group: "Operations", method: "GET", path: "/api/agents",             purpose: "Agent registry" },
  { id: "/api/dashboard/overview", group: "Dashboard",  method: "GET", path: "/api/dashboard/overview", purpose: "Dashboard counters + activity" },
  { id: "/api/nexus-map",          group: "Dashboard",  method: "GET", path: "/api/nexus-map",          purpose: "Universe view nodes + edges" },
  { id: "/api/llm/models",         group: "System",     method: "GET", path: "/api/llm/models",         purpose: "Available LLM models" },
  { id: "/api/mentions/search",    group: "System",     method: "GET", path: "/api/mentions/search",    purpose: "@-mention picker" },
  { id: "/api/search",             group: "System",     method: "GET", path: "/api/search?q=test",      purpose: "Unified Cmd-K search" },
  { id: "/api/arena/log",          group: "System",     method: "GET", path: "/api/arena/log",          purpose: "Arena executor audit log" },
]
