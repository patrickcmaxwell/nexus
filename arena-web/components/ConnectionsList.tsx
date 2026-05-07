"use client"

import { useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { Plus, Trash2, Loader2, CheckCircle2, AlertTriangle, Pencil } from "lucide-react"

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
    if (!confirm("Remove this connection? Eve will stop being able to act through this provider.")) return
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

  // Show provider catalog cards: connected ones first, available ones below.
  const connectedByProvider: Record<string, Connection[]> = {}
  for (const c of connections) {
    connectedByProvider[c.provider] = connectedByProvider[c.provider] || []
    connectedByProvider[c.provider].push(c)
  }

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
      {providers.map((p) => {
        const conns = connectedByProvider[p.id] ?? []
        return (
          <div key={p.id} className="p-4 border" style={{ borderColor: `${p.accent}33`, background: `${p.accent}08` }}>
            <div className="flex items-center justify-between mb-2">
              <div>
                <p className="font-mono text-[10px] tracking-[0.2em] uppercase" style={{ color: p.accent }}>
                  {p.name}
                </p>
                <p className="text-sm text-white/65 mt-0.5">{p.description}</p>
              </div>
              <Link href={`/connect/${p.id}`}
                className="font-mono text-[10px] tracking-[0.2em] uppercase px-2 py-1 flex items-center gap-1.5"
                style={{ color: p.accent, border: `1px solid ${p.accent}55` }}
              >
                <Plus size={11} /> Add
              </Link>
            </div>

            {conns.length === 0 ? (
              <p className="text-xs text-white/40 mt-3">No active connections. Click Add to wire one.</p>
            ) : (
              <ul className="mt-3 flex flex-col gap-1.5">
                {conns.map((c) => (
                  <li key={c.id} className="flex items-center justify-between px-3 py-2 bg-white/[0.04]">
                    <div className="flex items-center gap-2 min-w-0">
                      {c.status === "active" ? (
                        <CheckCircle2 size={12} className="text-emerald-400 shrink-0" />
                      ) : (
                        <AlertTriangle size={12} className="text-amber-400 shrink-0" />
                      )}
                      <div className="min-w-0">
                        <p className="text-sm text-white/85 truncate">{c.label ?? "Default"}</p>
                        <p className="text-[10px] text-white/40 font-mono uppercase tracking-wider">
                          {c.last_used_at ? `Last used ${relative(c.last_used_at)}` : "Never used"}
                        </p>
                      </div>
                    </div>
                    <div className="flex items-center gap-1">
                      <Link
                        href={`/connect/${c.provider}/${c.id}/edit`}
                        className="text-white/35 hover:text-white/85 p-1"
                        title="Edit / rotate credentials"
                      >
                        <Pencil size={12} />
                      </Link>
                      <button
                        onClick={() => remove(c.id)}
                        disabled={removing === c.id}
                        className="text-white/35 hover:text-red-400 disabled:opacity-40 p-1"
                        title="Remove connection"
                      >
                        {removing === c.id ? <Loader2 size={12} className="animate-spin" /> : <Trash2 size={12} />}
                      </button>
                    </div>
                  </li>
                ))}
              </ul>
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
