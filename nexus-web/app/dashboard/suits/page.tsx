import Link from "next/link"
import { redirect } from "next/navigation"
import { getActiveAuthId } from "@/lib/auth/session"
import { createServiceClient } from "@/lib/supabase/service"
import SuitsClient from "@/components/dashboard/SuitsClient"

export const dynamic = "force-dynamic"

// Suits = the user's deployable agent personas, rendered through the
// HUD-armor lens. Same `agents` table that powers /dashboard/agents — this
// is just an alternate visual treatment focused on "what can I deploy?"
// rather than "what's their personality?"
export default async function SuitsPage() {
  const userId = await getActiveAuthId()
  if (!userId) redirect("/auth/login")

  const supabase = createServiceClient()
  const { data: agents } = await supabase
    .from("agents")
    .select("id, name, role, status, capabilities, personality, directives")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })

  return <SuitsClient agents={agents ?? []} />
}
