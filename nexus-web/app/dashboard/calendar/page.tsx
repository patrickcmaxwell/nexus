import { redirect } from "next/navigation"
import { getActiveAuthId } from "@/lib/auth/session"
import { createServiceClient } from "@/lib/supabase/service"
import CalendarClient from "@/components/dashboard/CalendarClient"

export const dynamic = "force-dynamic"

// Calendar page — view + manage scheduled actions (Operation Calendar).
//
// Loads:
//   - all schedules owned by the active user (newest first)
//   - the user's eve_conversations (for the "post to chat" target picker)
//   - the user's agents and operations (for those target pickers)
//
// External calendar events (Google / Apple) will appear here too once
// Arena providers for those land — same table, different created_by.

export default async function CalendarPage() {
  const userId = await getActiveAuthId()
  if (!userId) redirect("/auth/login")

  const supabase = createServiceClient()
  const [schedulesRes, convsRes, agentsRes, opsRes] = await Promise.all([
    supabase
      .from("schedules")
      .select("id, name, description, cron_expression, timezone, target_type, target_id, payload, enabled, next_run_at, last_run_at, last_status, last_error, created_at")
      .eq("user_id", userId)
      .order("created_at", { ascending: false }),
    supabase
      .from("eve_conversations")
      .select("id, title")
      .eq("user_id", userId)
      .order("updated_at", { ascending: false })
      .limit(50),
    supabase
      .from("agents")
      .select("id, name")
      .eq("user_id", userId)
      .order("created_at", { ascending: false }),
    supabase
      .from("operations")
      .select("id, name")
      .eq("user_id", userId)
      .order("updated_at", { ascending: false }),
  ])

  return (
    <CalendarClient
      initialSchedules={schedulesRes.data ?? []}
      conversations={convsRes.data ?? []}
      agents={agentsRes.data ?? []}
      operations={opsRes.data ?? []}
    />
  )
}
