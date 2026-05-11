"use client"

// Connections grid. One card per registered provider, showing connected
// instances + an Add button. Clean Apple/Linear style — no per-provider
// color tints, no HUD label chrome. The brand color shows up only on the
// status dot for the connected state.

import { useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import {
  Plus, Trash2, Loader2, CheckCircle2, AlertTriangle, ChevronRight,
  ListChecks, FileText, Github, CreditCard, MessageSquare,
} from "lucide-react"

type Connection = {
  id: string
  provider: string
  label: string | null
  status: string
  last_used_at: string | null
  last_error: string | null
  created_at: string
}

type ProviderInfo = {
  id: string
  name: string
  description: string
  icon: string
  accent: string
}

const ICONS: Record<string, React.ComponentType<{ size?: number; className?: string }>> = {
  "list-checks":   ListChecks,
  "file-text":     FileText,
  "github":        Github,
  "credit-card":   CreditCard,
  "message-square": MessageSquare,
}

export default function ConnectionsList({
  initial, providers,
}: {
  initial: Connection[]
  providers: ProviderInfo[]
}) {
  const router = useRouter()
  const [connections, setConnections] = useState<Connection[]>(initial)
  const [removing, setRemoving] = useState<string | null>(null)

  async function remove(id: string) {
    if (!confirm("Remove this connection? Eve will lose the ability to act through it. Past actions stay in the audit log.")) return
    setRemoving(id)
    try {
      const res = await fetch(`/api/connections?id=${id}`, { method: "DELETE" })
      if (res.ok) {
        setConnections((c) => c.filter((x) => x.id !== id))
        router.refresh()
      }
    } finally {
      setRemoving(null)
    }
  }

  const connectedByProvider: Record<string, Connection[]> = {}
  for (const c of connections) {
    connectedByProvider[c.provider] = connectedByProvider[c.provider] || []
    connectedByProvider[c.provider].push(c)
  }

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
      {providers.map((p) => {
        const conns = connectedByProvider[p.id] ?? []
        const Icon = ICONS[p.icon] ?? ListChecks
        const connectHref =
          p.id === "clickup" ? "/connect/clickup"
          : p.id === "notion" ? "/connect/notion"
          : p.id === "github" ? "/connect/github"
          : p.id === "slack"  ? "/connect/slack"
          : `/connect/${p.id}`
        const isConnected = conns.length > 0

        return (
          <div key={p.id} className="rounded-[14px] bg-[color:var(--color-surface)] border border-[color:var(--color-border)] hover:border-[color:var(--color-border-2)] transition-colors overflow-hidden">
            <div className="p-5">
              <div className="flex items-start gap-3 mb-1">
                <div className="w-9 h-9 rounded-lg bg-[color:var(--color-surface-2)] flex items-center justify-center flex-shrink-0">
                  <Icon size={17} className="text-[color:var(--color-fg)]" />
                </div>
                <div className="min-w-0 flex-1">
                  <p className="text-base font-medium text-[color:var(--color-fg)] leading-tight">
                    {p.name}
                  </p>
                  <p className="text-sm text-[color:var(--color-fg-muted)] mt-1 leading-snug">
                    {p.description}
                  </p>
                </div>
              </div>
            </div>

            {isConnected ? (
              <ul className="border-t border-[color:var(--color-border)]">
                {conns.map((c) => (
                  <li
                    key={c.id}
                    className="flex items-center gap-3 px-5 py-3 border-b border-[color:var(--color-border)] last:border-b-0 hover:bg-[color:var(--color-surface-2)] transition-colors"
                  >
                    <span
                      className={`w-2 h-2 rounded-full flex-shrink-0 ${
                        c.status === "active" ? "bg-[color:var(--color-success)]" : "bg-[color:var(--color-warning)]"
                      }`}
                      title={c.status}
                    />
                    <div className="min-w-0 flex-1">
                      <p className="text-sm text-[color:var(--color-fg)] truncate">{c.label ?? "Default"}</p>
                      <p className="text-xs text-[color:var(--color-fg-subtle)] mt-0.5">
                        {c.last_used_at ? `Last used ${relative(c.last_used_at)}` : "Not used yet"}
                      </p>
                    </div>
                    <Link
                      href={
                        c.provider === "clickup" ? `/connect/clickup/${c.id}/settings` :
                        c.provider === "notion"  ? `/connect/notion/${c.id}/settings` :
                        c.provider === "github"  ? `/connect/github/${c.id}/settings` :
                        c.provider === "slack"   ? `/connect/slack/${c.id}/settings` :
                        `/connect/${c.provider}/${c.id}/edit`
                      }
                      className="text-sm text-[color:var(--color-fg-muted)] hover:text-[color:var(--color-fg)] transition-colors flex items-center gap-1"
                    >
                      Settings
                      <ChevronRight size={14} />
                    </Link>
                    <button
                      onClick={() => remove(c.id)}
                      disabled={removing === c.id}
                      className="p-1.5 rounded-md text-[color:var(--color-fg-subtle)] hover:text-[color:var(--color-danger)] hover:bg-[color:var(--color-danger)]/10 disabled:opacity-40 transition-colors"
                      title="Remove connection"
                    >
                      {removing === c.id ? <Loader2 size={14} className="animate-spin" /> : <Trash2 size={14} />}
                    </button>
                  </li>
                ))}
                <li className="px-5 py-3 border-t border-[color:var(--color-border)] bg-[color:var(--color-bg)]/40">
                  <Link
                    href={connectHref}
                    className="text-sm text-[color:var(--color-accent)] hover:underline inline-flex items-center gap-1.5"
                  >
                    <Plus size={13} /> Add another {p.name} connection
                  </Link>
                </li>
              </ul>
            ) : (
              <div className="border-t border-[color:var(--color-border)] bg-[color:var(--color-bg)]/40 px-5 py-3">
                <Link
                  href={connectHref}
                  className="text-sm text-[color:var(--color-accent)] hover:underline inline-flex items-center gap-1.5"
                >
                  <Plus size={13} /> Connect {p.name}
                </Link>
              </div>
            )}
          </div>
        )
      })}
    </div>
  )
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
