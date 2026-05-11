"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import {
  CheckCircle2, AlertTriangle, Loader2, Copy, Webhook, Trash2,
  RefreshCcw, Database,
} from "lucide-react"

type DatabaseEntry = { id: string; title: string; url?: string }

export default function NotionSettingsClient({
  connectionId, initialConfig, initialLabel, webhookSecret, usingOauth, justConnected,
}: {
  connectionId: string
  initialConfig: Record<string, unknown>
  initialLabel: string | null
  webhookSecret: string | null
  usingOauth: boolean
  justConnected: boolean
}) {
  const router = useRouter()
  const [label, setLabel]                 = useState(initialLabel ?? "")
  const [databaseId, setDatabaseId]       = useState((initialConfig.database_id as string | undefined) ?? "")
  const [titleProperty, setTitleProperty] = useState((initialConfig.title_property as string | undefined) ?? "Name")
  const [statusProperty, setStatusProperty] = useState((initialConfig.status_property as string | undefined) ?? "")

  const [databases, setDatabases]         = useState<DatabaseEntry[]>([])
  const [dbsLoading, setDbsLoading]       = useState(false)
  const [dbsError, setDbsError]           = useState<string | null>(null)

  const [saving, setSaving]               = useState(false)
  const [savedFlash, setSavedFlash]       = useState(false)
  const [error, setError]                 = useState<string | null>(null)
  const [copied, setCopied]               = useState(false)
  const [removing, setRemoving]           = useState(false)

  useEffect(() => {
    let cancelled = false
    async function load() {
      setDbsLoading(true)
      setDbsError(null)
      try {
        const url = new URL("/api/oauth/notion/databases", window.location.origin)
        url.searchParams.set("connection_id", connectionId)
        const res = await fetch(url.toString())
        const data = await res.json()
        if (cancelled) return
        if (!res.ok) {
          setDbsError(data.error || `HTTP ${res.status}`)
          setDatabases([])
        } else {
          setDatabases(data.databases as DatabaseEntry[])
        }
      } catch (err) {
        if (cancelled) return
        setDbsError(err instanceof Error ? err.message : "Network error")
      } finally {
        if (!cancelled) setDbsLoading(false)
      }
    }
    if (usingOauth) load()
    return () => { cancelled = true }
  }, [connectionId, usingOauth])

  const webhookUrl = webhookSecret && typeof window !== "undefined"
    ? `${window.location.origin}/api/webhooks/${connectionId}/${webhookSecret}`
    : null

  async function copyWebhook() {
    if (!webhookUrl) return
    try {
      await navigator.clipboard.writeText(webhookUrl)
      setCopied(true)
      setTimeout(() => setCopied(false), 1500)
    } catch { /* ignore */ }
  }

  async function save() {
    setSaving(true)
    setError(null)
    try {
      const res = await fetch(`/api/connections/${connectionId}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          label: label.trim() || null,
          values: {
            database_id: databaseId,
            title_property: titleProperty,
            status_property: statusProperty,
          },
        }),
      })
      const data = await res.json().catch(() => ({}))
      if (!res.ok) {
        setError(data.error || `HTTP ${res.status}`)
        return
      }
      setSavedFlash(true)
      setTimeout(() => setSavedFlash(false), 2500)
      router.refresh()
    } catch (err) {
      setError(err instanceof Error ? err.message : "Network error")
    } finally {
      setSaving(false)
    }
  }

  async function remove() {
    if (!confirm("Remove this Notion connection? Eve will lose access. Past actions stay in the audit log.")) return
    setRemoving(true)
    try {
      const res = await fetch(`/api/connections?id=${connectionId}`, { method: "DELETE" })
      if (res.ok) router.push("/connect/notion")
    } finally {
      setRemoving(false)
    }
  }

  const selectedDbName = databases.find(d => d.id === databaseId)?.title

  return (
    <div className="flex flex-col gap-6">
      {justConnected && (
        <div className="surface-flush border-[color:var(--color-success)]/40 p-4 flex items-start gap-3">
          <CheckCircle2 size={18} className="text-[color:var(--color-success)] flex-shrink-0 mt-0.5" />
          <div>
            <p className="text-sm font-medium text-[color:var(--color-fg)]">Connected</p>
            <p className="text-sm text-[color:var(--color-fg-muted)] mt-1">
              Pick a default database below so Eve knows where to drop pages unless you tell her otherwise.
            </p>
          </div>
        </div>
      )}

      {error && (
        <div className="surface-flush border-[color:var(--color-danger)]/40 p-4 flex items-start gap-3">
          <AlertTriangle size={18} className="text-[color:var(--color-danger)] flex-shrink-0 mt-0.5" />
          <p className="text-sm text-[color:var(--color-fg)]">{error}</p>
        </div>
      )}

      {/* DEFAULT DATABASE */}
      <section className="surface p-5">
        <div className="flex items-center justify-between mb-3">
          <div>
            <p className="label" style={{ marginBottom: 4 }}>Default database</p>
            <p className="helper" style={{ marginTop: 0 }}>
              Eve creates pages here unless she specifies another database. Only databases shared with the integration appear.
            </p>
          </div>
        </div>

        {!usingOauth ? (
          <p className="text-sm text-[color:var(--color-fg-muted)]">
            Live database picker requires OAuth. Use the manual edit page to set <code>database_id</code> by hand.
          </p>
        ) : dbsLoading ? (
          <div className="flex items-center gap-2 text-sm text-[color:var(--color-fg-muted)] py-2">
            <Loader2 size={14} className="animate-spin" />
            Loading databases from Notion…
          </div>
        ) : dbsError ? (
          <div className="flex items-start gap-2 text-sm text-[color:var(--color-danger)]">
            <AlertTriangle size={14} className="flex-shrink-0 mt-0.5" />
            <p>{dbsError}</p>
          </div>
        ) : databases.length === 0 ? (
          <div className="flex flex-col gap-2">
            <p className="text-sm text-[color:var(--color-fg-muted)]">
              No databases shared with this integration yet. In Notion: open the database → ⋯ menu → <strong>Add connections</strong> → pick this integration.
            </p>
          </div>
        ) : (
          <>
            <select
              value={databaseId}
              onChange={e => setDatabaseId(e.target.value)}
              className="input"
            >
              <option value="">— choose a database —</option>
              {databases.map(d => (
                <option key={d.id} value={d.id}>{d.title}</option>
              ))}
            </select>
            {selectedDbName && (
              <p className="helper flex items-center gap-1.5">
                <Database size={11} /> Eve will create pages in &ldquo;{selectedDbName}&rdquo;
              </p>
            )}
          </>
        )}
      </section>

      {/* PROPERTY MAPPING */}
      <section className="surface p-5">
        <p className="label" style={{ marginBottom: 4 }}>Property names</p>
        <p className="helper" style={{ marginTop: 0, marginBottom: 16 }}>
          Notion lets you rename columns. Tell us what your title and status columns are called so Eve writes them correctly.
        </p>
        <div className="flex flex-col gap-3">
          <label className="flex flex-col gap-1.5">
            <span className="text-sm text-[color:var(--color-fg)]">Title column name</span>
            <input
              type="text"
              value={titleProperty}
              onChange={e => setTitleProperty(e.target.value)}
              placeholder="Name"
              className="input"
            />
          </label>
          <label className="flex flex-col gap-1.5">
            <span className="text-sm text-[color:var(--color-fg)]">Status column name <span className="text-[color:var(--color-fg-subtle)]">(optional)</span></span>
            <input
              type="text"
              value={statusProperty}
              onChange={e => setStatusProperty(e.target.value)}
              placeholder="Status"
              className="input"
            />
          </label>
        </div>
      </section>

      {/* LABEL */}
      <section className="surface p-5">
        <label className="label" htmlFor="label">Friendly name</label>
        <p className="helper" style={{ marginTop: 0, marginBottom: 12 }}>
          Helps you tell connections apart when you have several. Optional.
        </p>
        <input
          id="label"
          type="text"
          value={label}
          onChange={e => setLabel(e.target.value)}
          placeholder="e.g. Personal Notion"
          className="input"
          maxLength={80}
        />
      </section>

      <div className="flex items-center justify-end gap-2 sticky bottom-4">
        {savedFlash && (
          <span className="text-sm text-[color:var(--color-success)] flex items-center gap-1.5">
            <CheckCircle2 size={14} /> Saved
          </span>
        )}
        <button onClick={save} disabled={saving} className="btn btn-primary">
          {saving ? <Loader2 size={14} className="animate-spin" /> : <CheckCircle2 size={14} />}
          Save changes
        </button>
      </div>

      {webhookUrl && (
        <section className="surface p-5">
          <div className="flex items-center gap-2 mb-2">
            <Webhook size={14} className="text-[color:var(--color-fg-muted)]" />
            <p className="label" style={{ marginBottom: 0 }}>Inbound webhook</p>
          </div>
          <p className="helper" style={{ marginTop: 0, marginBottom: 12 }}>
            Notion doesn&apos;t officially support webhooks yet, but if your team uses a relay (Zapier, n8n, etc.) you can have it POST to this URL.
          </p>
          <div className="flex gap-2">
            <input
              readOnly
              value={webhookUrl}
              onFocus={(e) => e.currentTarget.select()}
              className="input font-mono text-xs"
            />
            <button onClick={copyWebhook} className="btn btn-secondary flex-shrink-0">
              {copied ? <CheckCircle2 size={13} className="text-[color:var(--color-success)]" /> : <Copy size={13} />}
              {copied ? "Copied" : "Copy"}
            </button>
          </div>
        </section>
      )}

      <section className="surface p-5 mt-8 border-[color:var(--color-danger)]/30">
        <p className="label" style={{ marginBottom: 4, color: "var(--color-danger)" }}>Disconnect</p>
        <p className="helper" style={{ marginTop: 0, marginBottom: 12 }}>
          Removes the connection and revokes Eve&apos;s access. Past audit log entries stay.
        </p>
        <button onClick={remove} disabled={removing} className="btn btn-danger-ghost">
          {removing ? <Loader2 size={14} className="animate-spin" /> : <Trash2 size={14} />}
          Disconnect Notion
        </button>
      </section>
    </div>
  )
}
