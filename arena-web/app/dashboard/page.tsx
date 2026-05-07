import { redirect } from "next/navigation"
import Link from "next/link"
import { getActiveHuman } from "@/lib/auth/session"
import { getServiceClient } from "@/lib/supabase/service"
import { ALL_PROVIDERS } from "@/lib/providers"
import ConnectionsList from "@/components/ConnectionsList"
import RecentActions from "@/components/RecentActions"
import FirstRunGuide from "@/components/FirstRunGuide"

export const dynamic = "force-dynamic"

// User dashboard: connections + recent actions.
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
    <main className="min-h-screen px-6 md:px-10 py-10 max-w-5xl mx-auto">
      <header className="mb-10 flex items-start justify-between">
        <div>
          <p className="font-mono text-[10px] tracking-[0.3em] uppercase text-[var(--arena-accent)] mb-1">
            Arena · Dashboard
          </p>
          <h1 className="text-2xl font-bold">
            {isFirstRun ? `Hello, ${firstName(me.displayName)}` : `Welcome back, ${firstName(me.displayName)}`}
          </h1>
          <p className="text-sm text-white/55 mt-1">
            {isFirstRun
              ? "Let's get Eve hands. Three steps below."
              : "Your connections, the actions Eve has taken, and what's still wireable."}
          </p>
        </div>
        <Link href="/" className="font-mono text-[10px] tracking-[0.2em] uppercase text-white/55 hover:text-white">
          ← Home
        </Link>
      </header>

      {isFirstRun && (
        <FirstRunGuide
          providers={ALL_PROVIDERS.map((p) => ({
            id: p.id, name: p.name, description: p.description, accent: p.accent,
          }))}
        />
      )}

      <section className="mb-10">
        <h2 className="font-mono text-[10px] tracking-[0.25em] uppercase text-[var(--arena-accent)] mb-3">
          Your Connections
        </h2>
        <ConnectionsList
          initial={connections}
          providers={ALL_PROVIDERS.map((p) => ({
            id: p.id, name: p.name, description: p.description, icon: p.icon, accent: p.accent,
          }))}
        />
      </section>

      <section>
        <h2 className="font-mono text-[10px] tracking-[0.25em] uppercase text-[var(--arena-accent)] mb-3">
          Recent Actions
        </h2>
        <RecentActions actions={actions} />
      </section>
    </main>
  )
}

function firstName(displayName: string): string {
  return displayName.split(/\s+/)[0] || displayName
}
