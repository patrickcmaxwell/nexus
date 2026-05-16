import { redirect, notFound } from "next/navigation"
import { getActiveHuman } from "@/lib/auth/session"
import { createPartybotServiceClient, partybotConfigured } from "@/lib/partybot-supabase/service"
import type { PartybotBot } from "@/lib/partybot-supabase/types"
import PartybotEditor from "@/components/dashboard/PartybotEditor"

export const dynamic = "force-dynamic"

export default async function PartybotEditPage({ params }: { params: Promise<{ id: string }> }) {
  const me = await getActiveHuman()
  if (!me) redirect("/auth/login")
  if (!me.isOwner) redirect("/dashboard")

  const { id } = await params
  if (!isUuid(id)) notFound()

  if (!partybotConfigured()) {
    redirect("/dashboard/partybot")
  }

  const supabase = createPartybotServiceClient()!
  const { data: bot } = await supabase
    .from("bots")
    .select("*")
    .eq("id", id)
    .single<PartybotBot>()

  if (!bot) notFound()

  return <PartybotEditor initialBot={bot} />
}

function isUuid(s: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s)
}
