// /connect/clickup/[id]/settings
//
// Post-OAuth (or post-manual) settings page for a single ClickUp connection.
// User picks default list (live-fetched from ClickUp), toggles Eve permissions,
// and sees the webhook URL + connection info.

import Link from "next/link"
import { notFound, redirect } from "next/navigation"
import { getActiveHuman } from "@/lib/auth/session"
import { getServiceClient } from "@/lib/supabase/service"
import ClickUpSettingsClient from "./ClickUpSettingsClient"

export const dynamic = "force-dynamic"

export default async function ClickUpSettingsPage({
  params,
  searchParams,
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
    .select("id, label, status, last_used_at, last_error, config, webhook_secret, created_at, credentials")
    .eq("id", id)
    .eq("user_id", me.authId)
    .eq("provider", "clickup")
    .maybeSingle()
  if (!conn) notFound()

  const config = (conn.config as Record<string, unknown>) ?? {}
  const credentials = (conn.credentials as Record<string, string>) ?? {}
  const usingOauth = !!credentials.access_token

  return (
    <main className="min-h-screen px-4 sm:px-6 py-10 max-w-3xl mx-auto">
      <Link
        href="/connect/clickup"
        className="inline-flex items-center gap-2 text-sm text-[color:var(--color-fg-muted)] hover:text-[color:var(--color-fg)] mb-8"
      >
        ← All ClickUp connections
      </Link>

      <header className="mb-8">
        <p className="text-sm text-[color:var(--color-fg-subtle)] mb-2">ClickUp settings</p>
        <h1 className="text-2xl font-semibold tracking-tight">
          {(config.clickup_username as string | undefined) || conn.label || "Connection"}
        </h1>
        <p className="text-sm text-[color:var(--color-fg-muted)] mt-2">
          {usingOauth
            ? "Connected via ClickUp OAuth. Token rotates if you revoke from ClickUp's Apps page."
            : "Connected via manual API token. Re-authorize to switch to OAuth."}
        </p>
      </header>

      <ClickUpSettingsClient
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
