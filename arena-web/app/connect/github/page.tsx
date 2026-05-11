import Link from "next/link"
import { redirect } from "next/navigation"
import { getActiveHuman } from "@/lib/auth/session"
import { getServiceClient } from "@/lib/supabase/service"
import GithubConnectClient from "./GithubConnectClient"

export const dynamic = "force-dynamic"

type ExistingConnection = {
  id: string
  label: string | null
  status: string
  githubLogin: string | null
  githubAvatar: string | null
  lastUsedAt: string | null
}

export default async function ConnectGithubPage({
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
    .eq("provider", "github")
    .order("created_at", { ascending: false })

  const existing: ExistingConnection[] = (rows ?? []).map(r => ({
    id: r.id,
    label: r.label as string | null,
    status: r.status as string,
    githubLogin: ((r.config as Record<string, unknown> | null)?.github_login as string | undefined) ?? null,
    githubAvatar: ((r.config as Record<string, unknown> | null)?.github_avatar as string | undefined) ?? null,
    lastUsedAt: r.last_used_at as string | null,
  }))

  const oauthAvailable = !!process.env.GITHUB_CLIENT_ID

  return (
    <main className="min-h-screen px-4 sm:px-6 py-12 max-w-2xl mx-auto">
      <Link
        href="/dashboard"
        className="inline-flex items-center gap-2 text-sm text-[color:var(--color-fg-muted)] hover:text-[color:var(--color-fg)] mb-10"
      >
        ← Dashboard
      </Link>

      <header className="mb-10">
        <p className="text-sm text-[color:var(--color-fg-subtle)] mb-2">Connect</p>
        <h1 className="text-3xl font-semibold tracking-tight">GitHub</h1>
        <p className="text-base text-[color:var(--color-fg-muted)] mt-3 max-w-lg leading-relaxed">
          Eve opens issues + comments in your GitHub repos. Sign in once with your GitHub account and pick a default repo.
        </p>
      </header>

      <GithubConnectClient
        existing={existing}
        oauthAvailable={oauthAvailable}
        initialError={error ?? null}
      />
    </main>
  )
}
