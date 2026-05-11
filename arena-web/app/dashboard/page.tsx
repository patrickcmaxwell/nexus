import { redirect } from "next/navigation"
import Link from "next/link"
import { getActiveHuman } from "@/lib/auth/session"
import { getServiceClient } from "@/lib/supabase/service"
import { ALL_PROVIDERS } from "@/lib/providers"
import ConnectionsList from "@/components/ConnectionsList"
import RecentActions from "@/components/RecentActions"
import FirstRunGuide from "@/components/FirstRunGuide"

export const dynamic = "force-dynamic"

// Arena dashboard — connections + recent action log.
// Clean baseline: Apple/Linear-style. No HUD chrome.
export default async function DashboardPage() {
  const me = await getActiveHuman()
  if (!me) redirect("/")

  const supabase = getServiceClient()
  const [connectionsRes, actionsRes] = await Promise.all([
    supabase
      .from("arena_connections")
      .select("id, provider, label, status, last_used_at, last_error, created_at")
      .eq("user_id", me.authId)
      .order("created_at", { ascending: false }),
    supabase
      .from("arena_action_log")
      .select("id, action, caller, status, result, error_msg, created_at")
      .order("created_at", { ascending: false })
      .limit(40),
  ])

  const connections = connectionsRes.data ?? []
  const actions = actionsRes.data ?? []
  const isFirstRun = connections.length === 0 && actions.length === 0

  return (
    <main className="min-h-screen px-4 sm:px-6 md:px-10 py-10 max-w-5xl mx-auto">
      <header className="mb-10 flex items-start justify-between gap-4">
        <div className="min-w-0">
          <h1 className="text-3xl font-semibold tracking-tight text-[color:var(--color-fg)]">
            {isFirstRun ? `Welcome, ${firstName(me.displayName)}` : `Hi, ${firstName(me.displayName)}`}
          </h1>
          <p className="text-base text-[color:var(--color-fg-muted)] mt-2 max-w-lg">
            {isFirstRun
              ? "Three steps below to get Eve doing real work."
              : "Connections, recent actions, and what's still wireable."}
          </p>
        </div>
        <Link
          href="https://portal.maxnexus.io"
          className="text-sm text-[color:var(--color-fg-muted)] hover:text-[color:var(--color-fg)] transition-colors flex-shrink-0"
        >
          ← Portal
        </Link>
      </header>

      {isFirstRun && (
        <FirstRunGuide
          providers={ALL_PROVIDERS.map((p) => ({
            id: p.id, name: p.name, description: p.description, accent: p.accent,
          }))}
        />
      )}

      <section className="mb-12">
        <div className="mb-4">
          <h2 className="text-lg font-semibold text-[color:var(--color-fg)]">Connections</h2>
          <p className="text-sm text-[color:var(--color-fg-muted)] mt-0.5">
            Services Eve can act through on your behalf.
          </p>
        </div>
        <ConnectionsList
          initial={connections}
          providers={ALL_PROVIDERS.map((p) => ({
            id: p.id, name: p.name, description: p.description, icon: p.icon, accent: p.accent,
          }))}
        />
      </section>

      <section>
        <div className="mb-4">
          <h2 className="text-lg font-semibold text-[color:var(--color-fg)]">Recent activity</h2>
          <p className="text-sm text-[color:var(--color-fg-muted)] mt-0.5">
            Every action Eve and other callers fired through Arena.
          </p>
        </div>
        <RecentActions actions={actions} />
      </section>
    </main>
  )
}

function firstName(displayName: string): string {
  return displayName.split(/\s+/)[0] || displayName
}
