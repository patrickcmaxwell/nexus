import { redirect } from "next/navigation"
import { createServiceClient } from "@/lib/supabase/service"
import { getActiveAuthId, getActiveHuman } from "@/lib/auth/session"
import MaxwellClient from "@/components/dashboard/MaxwellClient"

export default async function MaxwellPage({
  searchParams,
}: {
  searchParams: Promise<{ c?: string }>
}) {
  const userId = await getActiveAuthId()
  if (!userId) redirect("/auth/login")

  const me = await getActiveHuman()
  const { c } = await searchParams
  const supabase = createServiceClient()

  // Pull avatar separately — getActiveHuman doesn't include it today.
  const { data: humanExtra } = me
    ? await supabase.from("humans").select("avatar_url").eq("id", me.humanId).single()
    : { data: null }

  // Load all conversations for the sidebar
  const { data: conversations } = await supabase
    .from("eve_conversations")
    .select("id, title, created_at, updated_at")
    .eq("user_id", userId)
    .order("updated_at", { ascending: false })
    .limit(500)

  // Use ?c= param if present, otherwise fall back to most recent
  const allConvs = conversations ?? []
  const targetId = c && allConvs.find((cv) => cv.id === c) ? c : allConvs[0]?.id ?? null
  let initialMessages: Array<{ id: string; role: string; content: string; created_at: string }> = []

  if (targetId) {
    const { data: history } = await supabase
      .from("eve_history")
      .select("id, role, content, created_at")
      .eq("user_id", userId)
      .eq("conversation_id", targetId)
      .order("created_at", { ascending: false })
      .limit(200)
    // Reverse so messages appear in chronological order (oldest first)
    initialMessages = (history ?? []).reverse()
  }

  return (
    <MaxwellClient
      conversations={allConvs}
      initialConversationId={targetId}
      initialMessages={initialMessages}
      userName={me?.displayName ?? "You"}
      userAvatarUrl={(humanExtra?.avatar_url as string | null | undefined) ?? null}
    />
  )
}
