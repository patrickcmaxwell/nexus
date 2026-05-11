"use client"

import Link from "next/link"
import { useState } from "react"
import { CheckCircle2, AlertTriangle, ArrowRight, Plus, Settings } from "lucide-react"

type ExistingConnection = {
  id: string
  label: string | null
  status: string
  teamName: string | null
  lastUsedAt: string | null
}

const ERROR_MESSAGES: Record<string, string> = {
  missing_code:           "Slack didn't return an authorization code — try again.",
  invalid_state:          "Security check failed. Try again from this page.",
  server_misconfigured:   "Arena is missing the Slack app credentials. Admin needs to set SLACK_CLIENT_ID + SLACK_CLIENT_SECRET on Vercel.",
  db_insert_failed:       "Couldn't save your new connection. Try again.",
  db_update_failed:       "Couldn't update an existing connection.",
  access_denied:          "You declined the Slack permission prompt.",
}

export default function SlackConnectClient({
  existing, oauthAvailable, initialError,
}: {
  existing: ExistingConnection[]
  oauthAvailable: boolean
  initialError: string | null
}) {
  const [error, setError] = useState<string | null>(initialError)
  const friendlyError = error ? (ERROR_MESSAGES[error] ?? `Sign-in failed: ${error}`) : null

  return (
    <div className="flex flex-col gap-6">
      {friendlyError && (
        <div className="surface-flush p-4 flex items-start gap-3 border-[color:var(--color-danger)]/40">
          <AlertTriangle size={18} className="text-[color:var(--color-danger)] flex-shrink-0 mt-0.5" />
          <div className="flex-1">
            <p className="text-sm text-[color:var(--color-fg)]">{friendlyError}</p>
            <button onClick={() => setError(null)} className="text-xs text-[color:var(--color-fg-subtle)] hover:text-[color:var(--color-fg)] mt-2">Dismiss</button>
          </div>
        </div>
      )}

      {existing.length > 0 && (
        <section className="flex flex-col gap-2">
          <p className="label">Your connected workspaces</p>
          {existing.map(c => (
            <Link key={c.id} href={`/connect/slack/${c.id}/settings`} className="surface flex items-center gap-3 p-4 hover:border-[color:var(--color-border-2)] transition-colors group">
              {c.status === "active" ? <CheckCircle2 size={18} className="text-[color:var(--color-success)] flex-shrink-0" /> : <AlertTriangle size={18} className="text-[color:var(--color-warning)] flex-shrink-0" />}
              <div className="flex-1 min-w-0">
                <p className="text-base text-[color:var(--color-fg)] truncate">{c.teamName || c.label || "Slack workspace"}</p>
                <p className="text-xs text-[color:var(--color-fg-subtle)] mt-0.5">{c.status === "active" ? "Connected" : `Status: ${c.status}`}{c.lastUsedAt && ` · last used ${relative(c.lastUsedAt)}`}</p>
              </div>
              <Settings size={16} className="text-[color:var(--color-fg-subtle)] group-hover:text-[color:var(--color-fg-muted)] flex-shrink-0" />
            </Link>
          ))}
        </section>
      )}

      <section className="surface p-6">
        {oauthAvailable ? (
          <div className="flex flex-col items-start gap-4">
            <div>
              <p className="text-base font-semibold text-[color:var(--color-fg)]">{existing.length === 0 ? "Add Eve to Slack" : "Add another workspace"}</p>
              <p className="text-sm text-[color:var(--color-fg-muted)] mt-1.5 max-w-md">
                Slack will ask which workspace and channels to grant Eve access to. Eve only posts where you invite her.
              </p>
            </div>
            <a href="/api/oauth/slack/start" className="btn btn-primary">
              <Plus size={15} />
              Add to Slack
              <ArrowRight size={14} className="opacity-70" />
            </a>
          </div>
        ) : (
          <div className="flex flex-col items-start gap-4 w-full">
            <div>
              <p className="text-base font-semibold text-[color:var(--color-fg)]">Slack sign-in isn&apos;t configured yet</p>
              <p className="text-sm text-[color:var(--color-fg-muted)] mt-1.5 max-w-md">
                Admin needs to register a Slack app once. After that everyone can add Eve to their workspace with one click.
              </p>
            </div>
            <div className="w-full surface-flush p-4 mt-2">
              <p className="text-sm font-semibold text-[color:var(--color-fg)] mb-3">Admin: register the Slack app</p>
              <ol className="flex flex-col gap-2.5 text-sm text-[color:var(--color-fg-muted)] leading-relaxed">
                <li className="flex gap-2.5">
                  <span className="flex-shrink-0 w-5 h-5 rounded-full bg-[color:var(--color-accent-soft)] text-[color:var(--color-accent)] text-xs font-semibold flex items-center justify-center">1</span>
                  <span>Open <a href="https://api.slack.com/apps" target="_blank" rel="noopener noreferrer" className="underline">api.slack.com/apps</a> → <strong>Create New App</strong> → <strong>From scratch</strong>. Name it (e.g. <em>Nexus Arena</em>) and pick your workspace.</span>
                </li>
                <li className="flex gap-2.5">
                  <span className="flex-shrink-0 w-5 h-5 rounded-full bg-[color:var(--color-accent-soft)] text-[color:var(--color-accent)] text-xs font-semibold flex items-center justify-center">2</span>
                  <span>
                    Sidebar → <strong>OAuth & Permissions</strong>. Under <strong>Redirect URLs</strong> add:
                    <code className="block mt-1.5 text-xs bg-[color:var(--color-bg)] px-2 py-1.5 rounded break-all font-mono">
                      https://arena.maxnexus.io/api/oauth/slack/callback
                    </code>
                  </span>
                </li>
                <li className="flex gap-2.5">
                  <span className="flex-shrink-0 w-5 h-5 rounded-full bg-[color:var(--color-accent-soft)] text-[color:var(--color-accent)] text-xs font-semibold flex items-center justify-center">3</span>
                  <span>
                    Same page → <strong>Bot Token Scopes</strong>. Add: <code className="text-xs bg-[color:var(--color-bg)] px-1.5 py-0.5 rounded">chat:write</code>, <code className="text-xs bg-[color:var(--color-bg)] px-1.5 py-0.5 rounded">chat:write.public</code>, <code className="text-xs bg-[color:var(--color-bg)] px-1.5 py-0.5 rounded">channels:read</code>, <code className="text-xs bg-[color:var(--color-bg)] px-1.5 py-0.5 rounded">groups:read</code>.
                  </span>
                </li>
                <li className="flex gap-2.5">
                  <span className="flex-shrink-0 w-5 h-5 rounded-full bg-[color:var(--color-accent-soft)] text-[color:var(--color-accent)] text-xs font-semibold flex items-center justify-center">4</span>
                  <span>Sidebar → <strong>Basic Information</strong>. Under <strong>App Credentials</strong>, copy <strong>Client ID</strong> and <strong>Client Secret</strong>.</span>
                </li>
                <li className="flex gap-2.5">
                  <span className="flex-shrink-0 w-5 h-5 rounded-full bg-[color:var(--color-accent-soft)] text-[color:var(--color-accent)] text-xs font-semibold flex items-center justify-center">5</span>
                  <span>
                    On the arena-web Vercel project, add two environment variables:
                    <code className="block mt-1.5 text-xs bg-[color:var(--color-bg)] px-2 py-1.5 rounded font-mono">SLACK_CLIENT_ID</code>
                    <code className="block mt-1 text-xs bg-[color:var(--color-bg)] px-2 py-1.5 rounded font-mono">SLACK_CLIENT_SECRET</code>
                  </span>
                </li>
                <li className="flex gap-2.5">
                  <span className="flex-shrink-0 w-5 h-5 rounded-full bg-[color:var(--color-accent-soft)] text-[color:var(--color-accent)] text-xs font-semibold flex items-center justify-center">6</span>
                  <span>Vercel will redeploy. Refresh this page — the &ldquo;Add to Slack&rdquo; button replaces these instructions.</span>
                </li>
              </ol>
              <p className="text-xs text-[color:var(--color-fg-subtle)] mt-3">
                Reference: <a href="https://docs.slack.dev/authentication/installing-with-oauth" target="_blank" rel="noopener noreferrer" className="underline">Slack OAuth v2 docs</a>
              </p>
            </div>
          </div>
        )}
      </section>
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
