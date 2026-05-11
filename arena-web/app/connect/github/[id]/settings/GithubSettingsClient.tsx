"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import {
  CheckCircle2, AlertTriangle, Loader2, Copy, Webhook, Trash2, Github, Lock,
} from "lucide-react"

type Repo = { id: number; full_name: string; private: boolean; description: string | null }

export default function GithubSettingsClient({
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
  const [label, setLabel] = useState(initialLabel ?? "")
  const [defaultRepo, setDefaultRepo] = useState((initialConfig.default_repo as string | undefined) ?? "")

  const [repos, setRepos] = useState<Repo[]>([])
  const [reposLoading, setReposLoading] = useState(false)
  const [reposError, setReposError] = useState<string | null>(null)

  const [saving, setSaving] = useState(false)
  const [savedFlash, setSavedFlash] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [copied, setCopied] = useState(false)
  const [removing, setRemoving] = useState(false)

  useEffect(() => {
    let cancelled = false
    async function load() {
      setReposLoading(true)
      setReposError(null)
      try {
        const url = new URL("/api/oauth/github/repos", window.location.origin)
        url.searchParams.set("connection_id", connectionId)
        const res = await fetch(url.toString())
        const data = await res.json()
        if (cancelled) return
        if (!res.ok) {
          setReposError(data.error || `HTTP ${res.status}`)
          setRepos([])
        } else {
          setRepos(data.repos as Repo[])
        }
      } catch (err) {
        if (cancelled) return
        setReposError(err instanceof Error ? err.message : "Network error")
      } finally {
        if (!cancelled) setReposLoading(false)
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
          values: { default_repo: defaultRepo },
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
    if (!confirm("Remove this GitHub connection? Eve will lose access. Past actions stay in the audit log.")) return
    setRemoving(true)
    try {
      const res = await fetch(`/api/connections?id=${connectionId}`, { method: "DELETE" })
      if (res.ok) router.push("/connect/github")
    } finally {
      setRemoving(false)
    }
  }

  const selectedRepo = repos.find(r => r.full_name === defaultRepo)

  return (
    <div className="flex flex-col gap-6">
      {justConnected && (
        <div className="surface-flush border-[color:var(--color-success)]/40 p-4 flex items-start gap-3">
          <CheckCircle2 size={18} className="text-[color:var(--color-success)] flex-shrink-0 mt-0.5" />
          <div>
            <p className="text-sm font-medium text-[color:var(--color-fg)]">Connected</p>
            <p className="text-sm text-[color:var(--color-fg-muted)] mt-1">
              Pick a default repo so Eve knows where to file issues unless you tell her otherwise.
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

      <section className="surface p-5">
        <p className="label" style={{ marginBottom: 4 }}>Default repository</p>
        <p className="helper" style={{ marginTop: 0, marginBottom: 12 }}>
          Eve creates issues here unless she specifies another repo.
        </p>

        {!usingOauth ? (
          <p className="text-sm text-[color:var(--color-fg-muted)]">
            Live repo picker requires OAuth. Use the manual edit page to set <code>default_repo</code> by hand (format: <code>owner/repo</code>).
          </p>
        ) : reposLoading ? (
          <div className="flex items-center gap-2 text-sm text-[color:var(--color-fg-muted)] py-2">
            <Loader2 size={14} className="animate-spin" />
            Loading repos from GitHub…
          </div>
        ) : reposError ? (
          <div className="flex items-start gap-2 text-sm text-[color:var(--color-danger)]">
            <AlertTriangle size={14} className="flex-shrink-0 mt-0.5" />
            <p>{reposError}</p>
          </div>
        ) : repos.length === 0 ? (
          <p className="text-sm text-[color:var(--color-fg-muted)]">No repos accessible to this token.</p>
        ) : (
          <>
            <select
              value={defaultRepo}
              onChange={e => setDefaultRepo(e.target.value)}
              className="input"
            >
              <option value="">— choose a repo —</option>
              {repos.map(r => (
                <option key={r.id} value={r.full_name}>
                  {r.private ? "🔒 " : ""}{r.full_name}
                </option>
              ))}
            </select>
            {selectedRepo && (
              <p className="helper flex items-center gap-1.5">
                {selectedRepo.private ? <Lock size={11} /> : <Github size={11} />}
                {selectedRepo.description || "No description"}
              </p>
            )}
          </>
        )}
      </section>

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
          placeholder="e.g. Personal GitHub"
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
            Paste this URL into GitHub repo Settings → Webhooks to feed events back into Arena&apos;s audit log.
          </p>
          <div className="flex gap-2">
            <input readOnly value={webhookUrl} onFocus={(e) => e.currentTarget.select()} className="input font-mono text-xs" />
            <button onClick={copyWebhook} className="btn btn-secondary flex-shrink-0">
              {copied ? <CheckCircle2 size={13} className="text-[color:var(--color-success)]" /> : <Copy size={13} />}
              {copied ? "Copied" : "Copy"}
            </button>
          </div>
        </section>
      )}

      <section className="surface p-5 mt-8 border-[color:var(--color-danger)]/30">
        <p className="label" style={{ marginBottom: 4, color: "var(--color-danger)" }}>Disconnect</p>
        <p className="helper" style={{ marginTop: 0, marginBottom: 12 }}>Removes the connection and revokes Eve&apos;s access.</p>
        <button onClick={remove} disabled={removing} className="btn btn-danger-ghost">
          {removing ? <Loader2 size={14} className="animate-spin" /> : <Trash2 size={14} />}
          Disconnect GitHub
        </button>
      </section>
    </div>
  )
}
