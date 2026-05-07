import { redirect } from "next/navigation"
import { getActiveHuman } from "@/lib/auth/session"
import { createServiceClient } from "@/lib/supabase/service"
import ArenaPanel from "@/components/dashboard/ArenaPanel"

export const dynamic = "force-dynamic"

export default async function ArenaPage() {
  const me = await getActiveHuman()
  if (!me) redirect("/auth/login")

  const supabase = createServiceClient()

  // Initial server-side fetch so the page paints with data, not a spinner.
  // arena_action_log is global (not per-user) — we filter caller-side as
  // needed; for now show all recent actions across the team.
  const [actionsRes, connectionsRes] = await Promise.all([
    supabase
      .from("arena_action_log")
      .select("id, action, caller, payload, result, status, error_msg, created_at")
      .order("created_at", { ascending: false })
      .limit(60),
    me.authId
      ? supabase
          .from("arena_connections")
          .select("id, provider, label, status, last_used_at, last_error, created_at")
          .eq("user_id", me.authId)
          .order("created_at", { ascending: false })
      : Promise.resolve({ data: [] as any[] }),
  ])

  return (
    <ArenaPanel
      initialActions={actionsRes.data ?? []}
      initialConnections={connectionsRes.data ?? []}
    />
  )
}
