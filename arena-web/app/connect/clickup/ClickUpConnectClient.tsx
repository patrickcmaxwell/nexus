"use client"

import Link from "next/link"
import { useState } from "react"
import { CheckCircle2, AlertTriangle, ArrowRight, Plus, Settings } from "lucide-react"

type ExistingConnection = {
  id: string
  label: string | null
  status: string
  clickupUsername: string | null
  lastUsedAt: string | null
}

const ERROR_MESSAGES: Record<string, string> = {
  missing_code:           "ClickUp didn't return an authorization code — try again.",
  invalid_state:          "Security check failed. The sign-in link may have expired or been opened in a different browser. Try again.",
  server_misconfigured:   "Arena is missing the ClickUp app credentials. The administrator needs to set CLICKUP_CLIENT_ID + CLICKUP_CLIENT_SECRET on Vercel.",
  db_insert_failed:       "Couldn't save your new connection. Try again, or check the audit log.",
  db_update_failed:       "Couldn't update an existing connection.",
  post_exchange_probe_failed: "Got a token from ClickUp but the follow-up call to verify it failed.",
  access_denied:          "You declined the ClickUp permission prompt. To use ClickUp from Eve, accept the prompt next time.",
}

export default function ClickUpConnectClient({
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
            <button
              onClick={() => setError(null)}
              className="text-xs text-[color:var(--color-fg-subtle)] hover:text-[color:var(--color-fg)] mt-2"
            >
              Dismiss
            </button>
          </div>
        </div>
      )}

      {existing.length > 0 && (
        <section className="flex flex-col gap-2">
          <p className="label">Your connected accounts</p>
          {existing.map(c => (
            <Link
              key={c.id}
              href={`/connect/clickup/${c.id}/settings`}
              className="surface flex items-center gap-3 p-4 hover:border-[color:var(--color-border-2)] transition-colors group"
            >
              {c.status === "active" ? (
                <CheckCircle2 size={18} className="text-[color:var(--color-success)] flex-shrink-0" />
              ) : (
                <AlertTriangle size={18} className="text-[color:var(--color-warning)] flex-shrink-0" />
              )}
              <div className="flex-1 min-w-0">
                <p className="text-base text-[color:var(--color-fg)] truncate">
                  {c.clickupUsername || c.label || "ClickUp connection"}
                </p>
                <p className="text-xs text-[color:var(--color-fg-subtle)] mt-0.5">
                  {c.status === "active" ? "Connected" : `Status: ${c.status}`}
                  {c.lastUsedAt && ` · last used ${relative(c.lastUsedAt)}`}
                </p>
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
              <p className="text-base font-semibold text-[color:var(--color-fg)]">
                {existing.length === 0 ? "Sign in with ClickUp" : "Add another account"}
              </p>
              <p className="text-sm text-[color:var(--color-fg-muted)] mt-1.5 max-w-md">
                You'll be redirected to ClickUp to grant access. Eve only sees the workspace you authorize.
              </p>
            </div>
            <a href="/api/oauth/clickup/start" className="btn btn-primary">
              {existing.length === 0 ? <Plus size={15} /> : <Plus size={15} />}
              Continue with ClickUp
              <ArrowRight size={14} className="opacity-70" />
            </a>
            <p className="text-xs text-[color:var(--color-fg-subtle)]">
              Prefer to paste an API token manually? <Link href="/connect/clickup/manual" className="underline hover:text-[color:var(--color-fg-muted)]">Use the legacy form</Link>.
            </p>
          </div>
        ) : (
          <div className="flex flex-col items-start gap-4 w-full">
            <div>
              <p className="text-base font-semibold text-[color:var(--color-fg)]">
                ClickUp sign-in isn&apos;t configured yet
              </p>
              <p className="text-sm text-[color:var(--color-fg-muted)] mt-1.5 max-w-md">
                The administrator needs to register a ClickUp OAuth app once. After that,
                everyone (you, your team) can sign in with one click below.
              </p>
            </div>

            <div className="w-full surface-flush p-4 mt-2">
              <p className="text-sm font-semibold text-[color:var(--color-fg)] mb-3">
                Admin: register the ClickUp app
              </p>
              <ol className="flex flex-col gap-2.5 text-sm text-[color:var(--color-fg-muted)] leading-relaxed">
                <li className="flex gap-2.5">
                  <span className="flex-shrink-0 w-5 h-5 rounded-full bg-[color:var(--color-accent-soft)] text-[color:var(--color-accent)] text-xs font-semibold flex items-center justify-center">1</span>
                  <span>
                    In ClickUp, click your <strong>avatar (upper-right)</strong> → <strong>Settings</strong>.
                  </span>
                </li>
                <li className="flex gap-2.5">
                  <span className="flex-shrink-0 w-5 h-5 rounded-full bg-[color:var(--color-accent-soft)] text-[color:var(--color-accent)] text-xs font-semibold flex items-center justify-center">2</span>
                  <span>
                    In the left sidebar, click <strong>Apps</strong>. Scroll down to find <strong>OAuth Apps</strong> → click <strong>Create new app</strong>.
                  </span>
                </li>
                <li className="flex gap-2.5">
                  <span className="flex-shrink-0 w-5 h-5 rounded-full bg-[color:var(--color-accent-soft)] text-[color:var(--color-accent)] text-xs font-semibold flex items-center justify-center">3</span>
                  <span>
                    App name: anything (e.g. <em>Nexus Arena</em>). Redirect URL (paste exactly):
                    <code className="block mt-1.5 text-xs bg-[color:var(--color-bg)] px-2 py-1.5 rounded break-all font-mono">
                      https://arena.maxnexus.io/api/oauth/clickup/callback
                    </code>
                  </span>
                </li>
                <li className="flex gap-2.5">
                  <span className="flex-shrink-0 w-5 h-5 rounded-full bg-[color:var(--color-accent-soft)] text-[color:var(--color-accent)] text-xs font-semibold flex items-center justify-center">4</span>
                  <span>
                    ClickUp shows a <strong>Client ID</strong> and <strong>Client Secret</strong>. Copy both.
                  </span>
                </li>
                <li className="flex gap-2.5">
                  <span className="flex-shrink-0 w-5 h-5 rounded-full bg-[color:var(--color-accent-soft)] text-[color:var(--color-accent)] text-xs font-semibold flex items-center justify-center">5</span>
                  <span>
                    On the arena-web Vercel project, add two environment variables:
                    <code className="block mt-1.5 text-xs bg-[color:var(--color-bg)] px-2 py-1.5 rounded font-mono">CLICKUP_CLIENT_ID</code>
                    <code className="block mt-1 text-xs bg-[color:var(--color-bg)] px-2 py-1.5 rounded font-mono">CLICKUP_CLIENT_SECRET</code>
                  </span>
                </li>
                <li className="flex gap-2.5">
                  <span className="flex-shrink-0 w-5 h-5 rounded-full bg-[color:var(--color-accent-soft)] text-[color:var(--color-accent)] text-xs font-semibold flex items-center justify-center">6</span>
                  <span>
                    Vercel will redeploy automatically. Refresh this page — the &ldquo;Continue with ClickUp&rdquo; button replaces these instructions.
                  </span>
                </li>
              </ol>
              <p className="text-xs text-[color:var(--color-fg-subtle)] mt-3">
                Reference: <a href="https://developer.clickup.com/docs/authentication" target="_blank" rel="noopener noreferrer" className="underline">ClickUp Authentication docs</a>
              </p>
            </div>

            <p className="text-xs text-[color:var(--color-fg-subtle)]">
              In a hurry?{" "}
              <Link href="/connect/clickup/manual" className="underline hover:text-[color:var(--color-fg-muted)]">
                Use a Personal API token
              </Link>
              {" "}— works only for your own account, doesn&apos;t require app registration.
            </p>
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
