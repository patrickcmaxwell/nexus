"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { CheckCircle2, AlertTriangle, Loader2, Trash2, Hash, Lock } from "lucide-react"

type Channel = { id: string; name: string; is_private: boolean }

export default function SlackSettingsClient({
  connectionId, initialConfig, initialLabel, usingOauth, justConnected,
}: {
  connectionId: string
  initialConfig: Record<string, unknown>
  initialLabel: string | null
  usingOauth: boolean
  justConnected: boolean
}) {
  const router = useRouter()
  const [label, setLabel] = useState(initialLabel ?? "")
  const [defaultChannel, setDefaultChannel] = useState((initialConfig.default_channel as string | undefined) ?? "")

  const [channels, setChannels] = useState<Channel[]>([])
  const [chsLoading, setChsLoading] = useState(false)
  const [chsError, setChsError] = useState<string | null>(null)

  const [saving, setSaving] = useState(false)
  const [savedFlash, setSavedFlash] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [removing, setRemoving] = useState(false)

  useEffect(() => {
    let cancelled = false
    async function load() {
      setChsLoading(true)
      setChsError(null)
      try {
        const url = new URL("/api/oauth/slack/channels", window.location.origin)
        url.searchParams.set("connection_id", connectionId)
        const res = await fetch(url.toString())
        const data = await res.json()
        if (cancelled) return
        if (!res.ok) {
          setChsError(data.error || `HTTP ${res.status}`)
          setChannels([])
        } else {
          setChannels(data.channels as Channel[])
        }
      } catch (err) {
        if (cancelled) return
        setChsError(err instanceof Error ? err.message : "Network error")
      } finally {
        if (!cancelled) setChsLoading(false)
      }
    }
    if (usingOauth) load()
    return () => { cancelled = true }
  }, [connectionId, usingOauth])

  async function save() {
    setSaving(true)
    setError(null)
    try {
      const res = await fetch(`/api/connections/${connectionId}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          label: label.trim() || null,
          values: { default_channel: defaultChannel },
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
    if (!confirm("Remove this Slack connection? Eve will lose access. Past actions stay in the audit log.")) return
    setRemoving(true)
    try {
      const res = await fetch(`/api/connections?id=${connectionId}`, { method: "DELETE" })
      if (res.ok) router.push("/connect/slack")
    } finally {
      setRemoving(false)
    }
  }

  const selectedChannel = channels.find(c => c.id === defaultChannel)

  return (
    <div className="flex flex-col gap-6">
      {justConnected && (
        <div className="surface-flush border-[color:var(--color-success)]/40 p-4 flex items-start gap-3">
          <CheckCircle2 size={18} className="text-[color:var(--color-success)] flex-shrink-0 mt-0.5" />
          <div>
            <p className="text-sm font-medium text-[color:var(--color-fg)]">Connected</p>
            <p className="text-sm text-[color:var(--color-fg-muted)] mt-1">Pick a default channel below.</p>
          </div>
        </div>
      )}

      {error && (
        <div className="surface-flush border-[color:var(--color-danger)]/40 p-4 flex items-start gap-3">
          <AlertTriangle size={18} className="text-[color:var(--color-danger)] flex-shrink-0 mt-0.5" />
          <p className="text-sm text-[color:var(--color-fg)]">{error}</p>
        </div>
      )}

      <section className="surface p-5">
        <p className="label" style={{ marginBottom: 4 }}>Default channel</p>
        <p className="helper" style={{ marginTop: 0, marginBottom: 12 }}>Eve posts here unless she specifies another channel. For private channels, you have to invite the bot first.</p>
        {!usingOauth ? (
          <p className="text-sm text-[color:var(--color-fg-muted)]">Live channel picker requires OAuth.</p>
        ) : chsLoading ? (
          <div className="flex items-center gap-2 text-sm text-[color:var(--color-fg-muted)] py-2">
            <Loader2 size={14} className="animate-spin" />
            Loading channels from Slack…
          </div>
        ) : chsError ? (
          <div className="flex items-start gap-2 text-sm text-[color:var(--color-danger)]">
            <AlertTriangle size={14} className="flex-shrink-0 mt-0.5" />
            <p>{chsError}</p>
          </div>
        ) : channels.length === 0 ? (
          <p className="text-sm text-[color:var(--color-fg-muted)]">No channels visible to this token. Invite the bot to a channel first.</p>
        ) : (
          <>
            <select value={defaultChannel} onChange={e => setDefaultChannel(e.target.value)} className="input">
              <option value="">— choose a channel —</option>
              {channels.map(c => (
                <option key={c.id} value={c.id}>
                  {c.is_private ? "🔒 " : "# "}{c.name}
                </option>
              ))}
            </select>
            {selectedChannel && (
              <p className="helper flex items-center gap-1.5">
                {selectedChannel.is_private ? <Lock size={11} /> : <Hash size={11} />}
                Eve will post in #{selectedChannel.name}
              </p>
            )}
          </>
        )}
      </section>

      <section className="surface p-5">
        <label className="label" htmlFor="label">Friendly name</label>
        <p className="helper" style={{ marginTop: 0, marginBottom: 12 }}>Helps you tell connections apart. Optional.</p>
        <input id="label" type="text" value={label} onChange={e => setLabel(e.target.value)} placeholder="e.g. Personal Slack" className="input" maxLength={80} />
      </section>

      <div className="flex items-center justify-end gap-2 sticky bottom-4">
        {savedFlash && <span className="text-sm text-[color:var(--color-success)] flex items-center gap-1.5"><CheckCircle2 size={14} /> Saved</span>}
        <button onClick={save} disabled={saving} className="btn btn-primary">
          {saving ? <Loader2 size={14} className="animate-spin" /> : <CheckCircle2 size={14} />}
          Save changes
        </button>
      </div>

      <section className="surface p-5 mt-8 border-[color:var(--color-danger)]/30">
        <p className="label" style={{ marginBottom: 4, color: "var(--color-danger)" }}>Disconnect</p>
        <p className="helper" style={{ marginTop: 0, marginBottom: 12 }}>Removes the connection and revokes Eve&apos;s access.</p>
        <button onClick={remove} disabled={removing} className="btn btn-danger-ghost">
          {removing ? <Loader2 size={14} className="animate-spin" /> : <Trash2 size={14} />}
          Disconnect Slack
        </button>
      </section>
    </div>
  )
}
