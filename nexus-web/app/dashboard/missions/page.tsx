import { createClient } from "@/lib/supabase/server"
import MissionsClient from "@/components/dashboard/MissionsClient"

export default async function MissionsPage() {
  const supabase = await createClient()
  const { data: missions } = await supabase
    .from("missions")
    .select("*")
    .order("created_at", { ascending: false })

  return <MissionsClient initialMissions={missions ?? []} />
}
