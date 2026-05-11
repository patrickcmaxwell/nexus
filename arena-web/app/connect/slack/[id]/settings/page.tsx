import Link from "next/link"
import { notFound, redirect } from "next/navigation"
import { getActiveHuman } from "@/lib/auth/session"
import { getServiceClient } from "@/lib/supabase/service"
import SlackSettingsClient from "./SlackSettingsClient"

export const dynamic = "force-dynamic"

export default async function SlackSettingsPage({
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
    .eq("provider", "slack")
    .maybeSingle()
  if (!conn) notFound()

  const config = (conn.config as Record<string, unknown>) ?? {}
  const credentials = (conn.credentials as Record<string, string>) ?? {}
  const usingOauth = !!credentials.access_token

  return (
    <main className="min-h-screen px-4 sm:px-6 py-10 max-w-3xl mx-auto">
      <Link href="/connect/slack" className="inline-flex items-center gap-2 text-sm text-[color:var(--color-fg-muted)] hover:text-[color:var(--color-fg)] mb-8">
        ← All Slack connections
      </Link>
      <header className="mb-8">
        <p className="text-sm text-[color:var(--color-fg-subtle)] mb-2">Slack settings</p>
        <h1 className="text-2xl font-semibold tracking-tight">{(config.team_name as string | undefined) || conn.label || "Workspace"}</h1>
        <p className="text-sm text-[color:var(--color-fg-muted)] mt-2">
          {usingOauth ? "Connected via Slack OAuth. Pick a default channel where Eve posts messages." : "Connected via legacy bot token."}
        </p>
      </header>
      <SlackSettingsClient
        connectionId={id}
        initialConfig={config}
        initialLabel={conn.label as string | null}
        usingOauth={usingOauth}
        justConnected={sp.just_connected === "1"}
      />
    </main>
  )
}
