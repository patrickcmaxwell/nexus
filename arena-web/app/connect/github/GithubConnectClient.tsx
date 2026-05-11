"use client"

import Link from "next/link"
import { useState } from "react"
import { CheckCircle2, AlertTriangle, ArrowRight, Plus, Settings } from "lucide-react"

type ExistingConnection = {
  id: string
  label: string | null
  status: string
  githubLogin: string | null
  githubAvatar: string | null
  lastUsedAt: string | null
}

const ERROR_MESSAGES: Record<string, string> = {
  missing_code:           "GitHub didn't return an authorization code — try again.",
  invalid_state:          "Security check failed. The sign-in link may have expired or been opened in a different browser. Try again.",
  server_misconfigured:   "Arena is missing the GitHub app credentials. The administrator needs to set GITHUB_CLIENT_ID + GITHUB_CLIENT_SECRET on Vercel.",
  db_insert_failed:       "Couldn't save your new connection. Try again.",
  db_update_failed:       "Couldn't update an existing connection.",
  access_denied:          "You declined the GitHub permission prompt. Accept it to continue.",
}

export default function GithubConnectClient({
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
          <p className="label">Your connected accounts</p>
          {existing.map(c => (
            <Link key={c.id} href={`/connect/github/${c.id}/settings`} className="surface flex items-center gap-3 p-4 hover:border-[color:var(--color-border-2)] transition-colors group">
              {c.status === "active" ? (
                <CheckCircle2 size={18} className="text-[color:var(--color-success)] flex-shrink-0" />
              ) : (
                <AlertTriangle size={18} className="text-[color:var(--color-warning)] flex-shrink-0" />
              )}
              {c.githubAvatar && (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={c.githubAvatar} alt="" className="w-8 h-8 rounded-full flex-shrink-0" />
              )}
              <div className="flex-1 min-w-0">
                <p className="text-base text-[color:var(--color-fg)] truncate">@{c.githubLogin || c.label || "github"}</p>
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
                {existing.length === 0 ? "Sign in with GitHub" : "Add another account"}
              </p>
              <p className="text-sm text-[color:var(--color-fg-muted)] mt-1.5 max-w-md">
                You&apos;ll be redirected to GitHub to grant access. Eve only acts in repos you authorize.
              </p>
            </div>
            <a href="/api/oauth/github/start" className="btn btn-primary">
              <Plus size={15} />
              Continue with GitHub
              <ArrowRight size={14} className="opacity-70" />
            </a>
            <p className="text-xs text-[color:var(--color-fg-subtle)]">
              Prefer to paste a Personal Access Token? <Link href="/connect/github/manual" className="underline hover:text-[color:var(--color-fg-muted)]">Use the legacy form</Link>.
            </p>
          </div>
        ) : (
          <div className="flex flex-col items-start gap-4 w-full">
            <div>
              <p className="text-base font-semibold text-[color:var(--color-fg)]">GitHub sign-in isn&apos;t configured yet</p>
              <p className="text-sm text-[color:var(--color-fg-muted)] mt-1.5 max-w-md">
                The administrator needs to register a GitHub OAuth App once. After that everyone can sign in with one click.
              </p>
            </div>

            <div className="w-full surface-flush p-4 mt-2">
              <p className="text-sm font-semibold text-[color:var(--color-fg)] mb-3">Admin: register the GitHub OAuth App</p>
              <ol className="flex flex-col gap-2.5 text-sm text-[color:var(--color-fg-muted)] leading-relaxed">
                <li className="flex gap-2.5">
                  <span className="flex-shrink-0 w-5 h-5 rounded-full bg-[color:var(--color-accent-soft)] text-[color:var(--color-accent)] text-xs font-semibold flex items-center justify-center">1</span>
                  <span>Open <a href="https://github.com/settings/developers" target="_blank" rel="noopener noreferrer" className="underline">github.com/settings/developers</a> → <strong>OAuth Apps</strong> → <strong>New OAuth App</strong>.</span>
                </li>
                <li className="flex gap-2.5">
                  <span className="flex-shrink-0 w-5 h-5 rounded-full bg-[color:var(--color-accent-soft)] text-[color:var(--color-accent)] text-xs font-semibold flex items-center justify-center">2</span>
                  <span>
                    Application name: anything (e.g. <em>Nexus Arena</em>). Homepage URL: <code className="text-xs bg-[color:var(--color-bg)] px-1.5 py-0.5 rounded">https://arena.maxnexus.io</code>. Authorization callback URL:
                    <code className="block mt-1.5 text-xs bg-[color:var(--color-bg)] px-2 py-1.5 rounded break-all font-mono">
                      https://arena.maxnexus.io/api/oauth/github/callback
                    </code>
                  </span>
                </li>
                <li className="flex gap-2.5">
                  <span className="flex-shrink-0 w-5 h-5 rounded-full bg-[color:var(--color-accent-soft)] text-[color:var(--color-accent)] text-xs font-semibold flex items-center justify-center">3</span>
                  <span>Save → GitHub shows a <strong>Client ID</strong>. Click <strong>Generate a new client secret</strong>. Copy both.</span>
                </li>
                <li className="flex gap-2.5">
                  <span className="flex-shrink-0 w-5 h-5 rounded-full bg-[color:var(--color-accent-soft)] text-[color:var(--color-accent)] text-xs font-semibold flex items-center justify-center">4</span>
                  <span>
                    On the arena-web Vercel project, add two environment variables:
                    <code className="block mt-1.5 text-xs bg-[color:var(--color-bg)] px-2 py-1.5 rounded font-mono">GITHUB_CLIENT_ID</code>
                    <code className="block mt-1 text-xs bg-[color:var(--color-bg)] px-2 py-1.5 rounded font-mono">GITHUB_CLIENT_SECRET</code>
                  </span>
                </li>
                <li className="flex gap-2.5">
                  <span className="flex-shrink-0 w-5 h-5 rounded-full bg-[color:var(--color-accent-soft)] text-[color:var(--color-accent)] text-xs font-semibold flex items-center justify-center">5</span>
                  <span>Vercel will redeploy. Refresh this page — the &ldquo;Continue with GitHub&rdquo; button replaces these instructions.</span>
                </li>
              </ol>
              <p className="text-xs text-[color:var(--color-fg-subtle)] mt-3">
                Reference: <a href="https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app" target="_blank" rel="noopener noreferrer" className="underline">GitHub OAuth Apps docs</a>
              </p>
            </div>

            <p className="text-xs text-[color:var(--color-fg-subtle)]">
              In a hurry? <Link href="/connect/github/manual" className="underline hover:text-[color:var(--color-fg-muted)]">Use a Personal Access Token</Link> — works only for your own GitHub.
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
