import { redirect } from "next/navigation"
import { getActiveHuman } from "@/lib/auth/session"
import { createServiceClient } from "@/lib/supabase/service"
import ConsoleClient from "@/components/dashboard/ConsoleClient"

export const dynamic = "force-dynamic"

export default async function ConsolePage() {
  const me = await getActiveHuman()
  if (!me) redirect("/auth/login")

  const supabase = createServiceClient()
  const { data: extra } = await supabase
    .from("humans")
    .select("avatar_url")
    .eq("id", me.humanId)
    .single()

  return (
    <ConsoleClient
      initial={{
        humanId:     me.humanId,
        email:       me.email,
        displayName: me.displayName,
        handle:      me.handle,
        role:        me.role,
        isOwner:     me.isOwner,
        authMethod:  me.authMethod,
        avatarUrl:   extra?.avatar_url ?? null,
      }}
    />
  )
}
