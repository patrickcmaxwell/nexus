"use client"

// Per-connection settings UI — picks default list from live ClickUp data,
// edits the friendly label, toggles per-action Eve permissions, exposes
// the inbound webhook URL with copy, and offers a destructive delete.

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import {
  CheckCircle2, AlertTriangle, Loader2, Copy, Webhook, Trash2,
  RefreshCcw, ListChecks,
} from "lucide-react"

type ListEntry = {
  id: string
  name: string
  spaceName: string
  folderName: string | null
}

type Team = { id: string; name: string }

type Permissions = {
  create_task: boolean
  update_task: boolean
}

const DEFAULT_PERMISSIONS: Permissions = {
  create_task: true,
  update_task: true,
}

export default function ClickUpSettingsClient({
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
  const [defaultListId, setDefaultListId] = useState((initialConfig.default_list_id as string | undefined) ?? "")
  const [defaultTeamId, setDefaultTeamId] = useState((initialConfig.default_team_id as string | undefined) ?? "")
  const [permissions, setPermissions]     = useState<Permissions>({
    ...DEFAULT_PERMISSIONS,
    ...((initialConfig.permissions as Partial<Permissions> | undefined) ?? {}),
  })
  const teams = (initialConfig.teams as Team[] | undefined) ?? []

  const [lists, setLists]                 = useState<ListEntry[]>([])
  const [listsLoading, setListsLoading]   = useState(false)
  const [listsError, setListsError]       = useState<string | null>(null)

  const [saving, setSaving]               = useState(false)
  const [savedFlash, setSavedFlash]       = useState(false)
  const [error, setError]                 = useState<string | null>(null)

  const [copied, setCopied]               = useState(false)
  const [removing, setRemoving]           = useState(false)

  // Load lists on mount + whenever team changes
  useEffect(() => {
    let cancelled = false
    async function load() {
      setListsLoading(true)
      setListsError(null)
      try {
        const url = new URL("/api/oauth/clickup/lists", window.location.origin)
        url.searchParams.set("connection_id", connectionId)
        if (defaultTeamId) url.searchParams.set("team_id", defaultTeamId)
        const res = await fetch(url.toString())
        const data = await res.json()
        if (cancelled) return
        if (!res.ok) {
          setListsError(data.error || `HTTP ${res.status}`)
          setLists([])
        } else {
          setLists(data.lists as ListEntry[])
        }
      } catch (err) {
        if (cancelled) return
        setListsError(err instanceof Error ? err.message : "Network error")
      } finally {
        if (!cancelled) setListsLoading(false)
      }
    }
    if (usingOauth) load()
    return () => { cancelled = true }
  }, [connectionId, defaultTeamId, usingOauth])

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
          // We need to send the existing per-field values via the existing
          // PATCH endpoint's `values` field. Send the config-only ones we've
          // changed; secret fields stay blank → preserved.
          values: {
            default_list_id: defaultListId,
            default_team_id: defaultTeamId,
            permissions: JSON.stringify(permissions),
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
    if (!confirm("Remove this ClickUp connection? Eve will lose access. Past actions stay in the audit log.")) return
    setRemoving(true)
    try {
      const res = await fetch(`/api/connections?id=${connectionId}`, { method: "DELETE" })
      if (res.ok) router.push("/connect/clickup")
    } finally {
      setRemoving(false)
    }
  }

  const selectedListLabel = lists.find(l => l.id === defaultListId)
    ? labelForList(lists.find(l => l.id === defaultListId)!)
    : null

  return (
    <div className="flex flex-col gap-6">
      {justConnected && (
        <div className="surface-flush border-[color:var(--color-success)]/40 p-4 flex items-start gap-3">
          <CheckCircle2 size={18} className="text-[color:var(--color-success)] flex-shrink-0 mt-0.5" />
          <div>
            <p className="text-sm font-medium text-[color:var(--color-fg)]">Connected</p>
            <p className="text-sm text-[color:var(--color-fg-muted)] mt-1">
              Pick a default list below so Eve knows where to drop tasks unless you tell her otherwise.
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

      {/* WORKSPACE / TEAM */}
      {teams.length > 1 && (
        <section className="surface p-5">
          <p className="label">Workspace</p>
          <p className="helper mb-3" style={{ marginTop: 0 }}>You authorized multiple ClickUp workspaces. Pick the one Eve should use.</p>
          <select
            value={defaultTeamId}
            onChange={e => { setDefaultTeamId(e.target.value); setDefaultListId("") }}
            className="input"
          >
            {teams.map(t => <option key={t.id} value={t.id}>{t.name}</option>)}
          </select>
        </section>
      )}

      {/* DEFAULT LIST */}
      <section className="surface p-5">
        <div className="flex items-center justify-between mb-3">
          <div>
            <p className="label" style={{ marginBottom: 4 }}>Default list</p>
            <p className="helper" style={{ marginTop: 0 }}>
              Eve drops tasks here unless she specifies another list.
            </p>
          </div>
          <button
            onClick={() => { setDefaultTeamId(defaultTeamId) /* trigger refetch */ }}
            className="btn btn-ghost"
            title="Refresh list from ClickUp"
            disabled={listsLoading}
          >
            <RefreshCcw size={13} className={listsLoading ? "animate-spin" : ""} />
          </button>
        </div>

        {!usingOauth ? (
          <p className="text-sm text-[color:var(--color-fg-muted)]">
            Live list picker requires the OAuth flow. Use the manual edit page to set <code>default_list_id</code> by hand.
          </p>
        ) : listsLoading ? (
          <div className="flex items-center gap-2 text-sm text-[color:var(--color-fg-muted)] py-2">
            <Loader2 size={14} className="animate-spin" />
            Loading lists from ClickUp…
          </div>
        ) : listsError ? (
          <div className="flex items-start gap-2 text-sm text-[color:var(--color-danger)]">
            <AlertTriangle size={14} className="flex-shrink-0 mt-0.5" />
            <p>{listsError}</p>
          </div>
        ) : lists.length === 0 ? (
          <p className="text-sm text-[color:var(--color-fg-muted)]">
            No lists found in this workspace. Create one in ClickUp first, then refresh.
          </p>
        ) : (
          <>
            <select
              value={defaultListId}
              onChange={e => setDefaultListId(e.target.value)}
              className="input"
            >
              <option value="">— choose a list —</option>
              {lists.map(l => (
                <option key={l.id} value={l.id}>{labelForList(l)}</option>
              ))}
            </select>
            {selectedListLabel && (
              <p className="helper flex items-center gap-1.5">
                <ListChecks size={11} /> Eve will create tasks in {selectedListLabel}
              </p>
            )}
          </>
        )}
      </section>

      {/* PERMISSIONS */}
      <section className="surface p-5">
        <p className="label" style={{ marginBottom: 4 }}>What Eve is allowed to do</p>
        <p className="helper" style={{ marginTop: 0, marginBottom: 16 }}>
          You can revoke any of these without disconnecting.
        </p>
        <div className="flex flex-col gap-3">
          <PermissionToggle
            label="Create tasks"
            description="Eve can add new tasks to your default list."
            value={permissions.create_task}
            onChange={v => setPermissions(p => ({ ...p, create_task: v }))}
          />
          <PermissionToggle
            label="Update tasks"
            description="Eve can change status, add comments, and resolve tasks she created."
            value={permissions.update_task}
            onChange={v => setPermissions(p => ({ ...p, update_task: v }))}
          />
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
          placeholder="e.g. Personal ClickUp"
          className="input"
          maxLength={80}
        />
      </section>

      {/* SAVE BAR */}
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

      {/* WEBHOOK */}
      {webhookUrl && (
        <section className="surface p-5">
          <div className="flex items-center gap-2 mb-2">
            <Webhook size={14} className="text-[color:var(--color-fg-muted)]" />
            <p className="label" style={{ marginBottom: 0 }}>Inbound webhook</p>
          </div>
          <p className="helper" style={{ marginTop: 0, marginBottom: 12 }}>
            Paste this URL into ClickUp&apos;s webhook settings to feed events back into Arena&apos;s audit log.
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

      {/* DANGER */}
      <section className="surface p-5 mt-8 border-[color:var(--color-danger)]/30">
        <p className="label" style={{ marginBottom: 4, color: "var(--color-danger)" }}>Disconnect</p>
        <p className="helper" style={{ marginTop: 0, marginBottom: 12 }}>
          Removes the connection and revokes Eve&apos;s access. Past audit log entries stay.
        </p>
        <button onClick={remove} disabled={removing} className="btn btn-danger-ghost">
          {removing ? <Loader2 size={14} className="animate-spin" /> : <Trash2 size={14} />}
          Disconnect ClickUp
        </button>
      </section>
    </div>
  )
}

function labelForList(l: ListEntry): string {
  const path = [l.spaceName, l.folderName, l.name].filter(Boolean).join(" / ")
  return path
}

function PermissionToggle({
  label, description, value, onChange,
}: {
  label: string; description: string; value: boolean; onChange: (v: boolean) => void
}) {
  return (
    <label className="flex items-start gap-3 cursor-pointer">
      <button
        type="button"
        role="switch"
        aria-checked={value}
        onClick={() => onChange(!value)}
        className="flex-shrink-0 w-10 h-6 rounded-full transition-colors mt-0.5"
        style={{
          background: value ? "var(--color-accent)" : "oklch(1 0 0 / 0.1)",
        }}
      >
        <span
          className="block w-4 h-4 rounded-full bg-white transition-transform shadow"
          style={{ transform: value ? "translateX(20px)" : "translateX(4px)" }}
        />
      </button>
      <div className="flex-1 min-w-0">
        <p className="text-sm text-[color:var(--color-fg)]">{label}</p>
        <p className="text-xs text-[color:var(--color-fg-muted)] mt-0.5">{description}</p>
      </div>
    </label>
  )
}
