import Link from "next/link"
import { redirect } from "next/navigation"
import { getActiveHuman } from "@/lib/auth/session"
import { getServiceClient } from "@/lib/supabase/service"
import SlackConnectClient from "./SlackConnectClient"

export const dynamic = "force-dynamic"

type ExistingConnection = {
  id: string
  label: string | null
  status: string
  teamName: string | null
  lastUsedAt: string | null
}

export default async function ConnectSlackPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>
}) {
  const me = await getActiveHuman()
  if (!me) redirect("/")
  const { error } = await searchParams

  const supabase = getServiceClient()
  const { data: rows } = await supabase
    .from("arena_connections")
    .select("id, label, status, last_used_at, config")
    .eq("user_id", me.authId)
    .eq("provider", "slack")
    .order("created_at", { ascending: false })

  const existing: ExistingConnection[] = (rows ?? []).map(r => ({
    id: r.id,
    label: r.label as string | null,
    status: r.status as string,
    teamName: ((r.config as Record<string, unknown> | null)?.team_name as string | undefined) ?? null,
    lastUsedAt: r.last_used_at as string | null,
  }))

  const oauthAvailable = !!process.env.SLACK_CLIENT_ID

  return (
    <main className="min-h-screen px-4 sm:px-6 py-12 max-w-2xl mx-auto">
      <Link href="/dashboard" className="inline-flex items-center gap-2 text-sm text-[color:var(--color-fg-muted)] hover:text-[color:var(--color-fg)] mb-10">
        ← Dashboard
      </Link>
      <header className="mb-10">
        <p className="text-sm text-[color:var(--color-fg-subtle)] mb-2">Connect</p>
        <h1 className="text-3xl font-semibold tracking-tight">Slack</h1>
        <p className="text-base text-[color:var(--color-fg-muted)] mt-3 max-w-lg leading-relaxed">
          Eve posts messages, reminders, and alerts to your Slack channel of choice.
        </p>
      </header>
      <SlackConnectClient existing={existing} oauthAvailable={oauthAvailable} initialError={error ?? null} />
    </main>
  )
}
