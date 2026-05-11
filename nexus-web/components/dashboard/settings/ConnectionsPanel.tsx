"use client"

import { useCallback, useEffect, useState } from "react"
import { Loader2, ExternalLink, Plug } from "lucide-react"

type Connection = {
  id: string
  provider: string
  label: string | null
  status: string
  last_used_at: string | null
  last_error: string | null
  created_at: string
}

type Provider = {
  id: string
  name: string
  methods?: string[]
}

type Payload = {
  connections: Connection[]
  providers: Provider[]
  manage_url: string
}

const ARENA_BASE = "https://arena.maxnexus.io"

export default function ConnectionsPanel() {
  const [data, setData] = useState<Payload | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const res = await fetch("/api/arena/connections", { cache: "no-store" })
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const json = (await res.json()) as Payload
      setData(json)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    load()
  }, [load])

  return (
    <section className="rounded-xl border border-border bg-card">
      <header className="flex items-center justify-between gap-3 px-5 py-4 border-b border-border">
        <div>
          <h3 className="text-sm font-semibold text-foreground">Authorized connections</h3>
          <p className="text-xs text-muted-foreground mt-0.5">
            Third-party services Eve and your agents can act on. Revoke any you don&apos;t want.
          </p>
        </div>
        <a
          href={data?.manage_url ?? `${ARENA_BASE}/dashboard`}
          target="_blank"
          rel="noopener noreferrer"
          className="text-xs text-muted-foreground hover:text-foreground inline-flex items-center gap-1"
        >
          Open Arena <ExternalLink size={11} />
        </a>
      </header>

      {error && (
        <div className="px-5 py-3 text-xs text-rose-400 border-b border-border">
          Couldn&apos;t load connections: {error}
        </div>
      )}

      {loading && !data ? (
        <div className="flex items-center gap-2 px-5 py-6 text-xs text-muted-foreground">
          <Loader2 size={14} className="animate-spin" /> Loading connections…
        </div>
      ) : data && data.connections.length === 0 ? (
        <div className="px-5 py-6 text-xs text-muted-foreground">
          No connections authorized yet.
          {data.providers.length > 0 && (
            <span className="ml-1">
              Available providers: {data.providers.map((p) => p.name).join(", ")}.
            </span>
          )}
        </div>
      ) : (
        <ul className="divide-y divide-border">
          {data?.connections.map((c) => (
            <li key={c.id} className="flex items-center gap-3 px-5 py-3">
              <div className="flex-none w-8 h-8 rounded-md bg-muted/50 border border-border flex items-center justify-center text-muted-foreground">
                <Plug size={15} />
              </div>
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2">
                  <span className="text-sm text-foreground truncate capitalize">
                    {c.provider}
                  </span>
                  {c.label && (
                    <span className="text-xs text-muted-foreground truncate">· {c.label}</span>
                  )}
                  <StatusPill status={c.status} />
                </div>
                <div className="text-[11px] text-muted-foreground mt-0.5 flex flex-wrap gap-x-2.5 gap-y-0.5">
                  <span>Connected {timeAgo(c.created_at)}</span>
                  {c.last_used_at && <span>Used {timeAgo(c.last_used_at)}</span>}
                  {c.last_error && <span className="text-rose-400 truncate">Last error: {c.last_error}</span>}
                </div>
              </div>
              <a
                href={`${ARENA_BASE}/connect/${c.provider}/${c.id}/settings`}
                target="_blank"
                rel="noopener noreferrer"
                className="flex-none inline-flex items-center gap-1 px-2.5 py-1.5 rounded-md text-xs text-muted-foreground hover:text-foreground hover:bg-muted transition-colors"
                title="Manage this connection"
              >
                Manage <ExternalLink size={11} />
              </a>
            </li>
          ))}
        </ul>
      )}
    </section>
  )
}

function StatusPill({ status }: { status: string }) {
  const tone =
    status === "active" ? "text-emerald-400 bg-emerald-500/10 border-emerald-500/30" :
    status === "error" ? "text-rose-400 bg-rose-500/10 border-rose-500/30" :
    "text-muted-foreground bg-muted/50 border-border"
  return (
    <span className={`text-[10px] uppercase tracking-wider px-1.5 py-0.5 rounded border ${tone}`}>
      {status}
    </span>
  )
}

function timeAgo(iso: string): string {
  const then = new Date(iso).getTime()
  const diff = Date.now() - then
  const m = Math.round(diff / 60_000)
  if (m < 1) return "just now"
  if (m < 60) return `${m}m ago`
  const h = Math.round(m / 60)
  if (h < 24) return `${h}h ago`
  const d = Math.round(h / 24)
  return `${d}d ago`
}
