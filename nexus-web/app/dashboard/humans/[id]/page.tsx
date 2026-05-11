// /dashboard/humans/[id] — per-member detail page.
//
// Owner/admin sees: profile + sessions + recent activity + admin actions.
// Members see their own page only (others 404).

import { notFound, redirect } from "next/navigation"
import Link from "next/link"
import { ChevronLeft } from "lucide-react"
import { getActiveHuman } from "@/lib/auth/session"
import { createServiceClient } from "@/lib/supabase/service"
import HumanDetailClient from "./HumanDetailClient"

export const dynamic = "force-dynamic"

type Member = {
  id: string
  display_name: string
  handle: string | null
  email: string | null
  role: string
  is_owner: boolean
  status: string
  avatar_url: string | null
  created_at: string
  last_active_at?: string | null
}

export default async function HumanDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const me = await getActiveHuman()
  if (!me) redirect("/auth/login")
  const { id } = await params

  const isAdminOrSelf = me.role === "admin" || me.isOwner || id === me.humanId
  if (!isAdminOrSelf) notFound()

  const supabase = createServiceClient()

  const { data: humanRow } = await supabase
    .from("humans")
    .select("id, display_name, handle, email, role, is_owner, status, avatar_url, created_at")
    .eq("id", id)
    .maybeSingle()

  if (!humanRow) notFound()

  const member = humanRow as Member

  // Sessions for this member (admin sees all; member sees their own only)
  const { data: sessions } = await supabase
    .from("security_sessions")
    .select("id, auth_method, last_verified_at, expires_at, invalidated, created_at")
    .eq("team_member_id", id)
    .order("last_verified_at", { ascending: false })
    .limit(20)

  // Recent activity: last conversations, last operations they touched
  // (best-effort; uses humans.auth_id when available since user-data tables
  // are scoped by auth_id, not humans.id).
  const { data: humanExtra } = await supabase
    .from("humans")
    .select("auth_id")
    .eq("id", id)
    .maybeSingle()
  const authId = (humanExtra?.auth_id as string | null) ?? null

  const { data: convs } = authId
    ? await supabase
        .from("eve_conversations")
        .select("id, title, updated_at")
        .eq("user_id", authId)
        .order("updated_at", { ascending: false })
        .limit(8)
    : { data: [] }

  const { data: ops } = authId
    ? await supabase
        .from("operations")
        .select("id, name, status, priority, updated_at")
        .eq("user_id", authId)
        .order("updated_at", { ascending: false })
        .limit(6)
    : { data: [] }

  const canManage = me.role === "admin" || me.isOwner
  const isSelf = id === me.humanId

  return (
    <main className="min-h-screen px-4 sm:px-6 md:px-10 py-8 max-w-5xl mx-auto">
      <Link
        href="/dashboard/humans"
        className="inline-flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground mb-6"
      >
        <ChevronLeft size={14} /> All humans
      </Link>

      <HumanDetailClient
        member={member}
        sessions={(sessions ?? []) as never}
        recentConversations={(convs ?? []) as never}
        recentOperations={(ops ?? []) as never}
        canManage={canManage}
        isSelf={isSelf}
      />
    </main>
  )
}
