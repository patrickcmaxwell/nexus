import { redirect } from "next/navigation"
import { createServiceClient } from "@/lib/supabase/service"
import { getActiveHuman } from "@/lib/auth/session"
import SettingsClient from "@/components/dashboard/SettingsClient"

export default async function SettingsPage() {
  const me = await getActiveHuman()
  if (!me) redirect("/auth/login")

  const supabase = createServiceClient()
  const { data: extra } = await supabase
    .from("humans")
    .select("avatar_url")
    .eq("id", me.humanId)
    .single()

  return (
    <SettingsClient
      initial={{
        humanId: me.humanId,
        email: me.email,
        displayName: me.displayName,
        handle: me.handle,
        role: me.role,
        isOwner: me.isOwner,
        authMethod: me.authMethod,
        avatarUrl: extra?.avatar_url ?? null,
      }}
    />
  )
}
