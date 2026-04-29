import { createServiceClient } from "@/lib/supabase/service"
import MaxwellClient from "@/components/dashboard/MaxwellClient"

const USER_ID = "e9d9a15b-0e5a-4631-9b50-6225ee03a44f"

export default async function MaxwellPage({
  searchParams,
}: {
  searchParams: Promise<{ c?: string }>
}) {
  const { c } = await searchParams
  const supabase = createServiceClient()

  // Load all conversations for the sidebar
  const { data: conversations } = await supabase
    .from("eve_conversations")
    .select("id, title, created_at, updated_at")
    .eq("user_id", USER_ID)
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
      .eq("user_id", USER_ID)
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
    />
  )
}
