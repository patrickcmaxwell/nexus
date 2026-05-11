import Link from "next/link"
import { notFound, redirect } from "next/navigation"
import { getActiveHuman } from "@/lib/auth/session"
import { getServiceClient } from "@/lib/supabase/service"
import GithubSettingsClient from "./GithubSettingsClient"

export const dynamic = "force-dynamic"

export default async function GithubSettingsPage({
  params, searchParams,
}: {
  params: Promise<{ id: string }>
  searchParams: Promise<{ just_connected?: string }>
}) {
  const me = await getActiveHuman()
  if (!me) redirect("/")
  const { id } = await params
  const sp = await searchParams

  const supabase = getServiceClient()
  const { data: conn } = await supabase
    .from("arena_connections")
    .select("id, label, status, last_used_at, last_error, config, webhook_secret, credentials")
    .eq("id", id)
    .eq("user_id", me.authId)
    .eq("provider", "github")
    .maybeSingle()
  if (!conn) notFound()

  const config = (conn.config as Record<string, unknown>) ?? {}
  const credentials = (conn.credentials as Record<string, string>) ?? {}
  const usingOauth = !!credentials.access_token

  return (
    <main className="min-h-screen px-4 sm:px-6 py-10 max-w-3xl mx-auto">
      <Link href="/connect/github" className="inline-flex items-center gap-2 text-sm text-[color:var(--color-fg-muted)] hover:text-[color:var(--color-fg)] mb-8">
        ← All GitHub connections
      </Link>

      <header className="mb-8 flex items-start gap-4">
        {(config.github_avatar as string | undefined) && (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={config.github_avatar as string} alt="" className="w-14 h-14 rounded-full flex-shrink-0" />
        )}
        <div>
          <p className="text-sm text-[color:var(--color-fg-subtle)] mb-1">GitHub settings</p>
          <h1 className="text-2xl font-semibold tracking-tight">@{(config.github_login as string | undefined) || conn.label || "connection"}</h1>
          <p className="text-sm text-[color:var(--color-fg-muted)] mt-2">
            {usingOauth
              ? "Connected via GitHub OAuth. Repos listed below are everything this account can access."
              : "Connected via Personal Access Token. Re-authorize to switch to OAuth."}
          </p>
        </div>
      </header>

      <GithubSettingsClient
        connectionId={id}
        initialConfig={config}
        initialLabel={conn.label as string | null}
        webhookSecret={conn.webhook_secret as string | null}
        usingOauth={usingOauth}
        justConnected={sp.just_connected === "1"}
      />
    </main>
  )
}
