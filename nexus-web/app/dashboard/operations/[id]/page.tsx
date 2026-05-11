// /dashboard/operations/[id] — full-page operation detail.
//
// The Operations index has a master-detail layout for quick browse. This
// route is the deep-dive: full directives, records timeline, briefs index,
// shareable URL.

import Link from "next/link"
import { notFound, redirect } from "next/navigation"
import { ChevronLeft, FileText, Clock } from "lucide-react"
import { getActiveAuthId } from "@/lib/auth/session"
import { createServiceClient } from "@/lib/supabase/service"
import OperationDetailClient from "./OperationDetailClient"

export const dynamic = "force-dynamic"

export default async function OperationDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const userId = await getActiveAuthId()
  if (!userId) redirect("/auth/login")
  const { id } = await params

  const supabase = createServiceClient()

  const { data: op } = await supabase
    .from("operations")
    .select("id, name, codename, description, objectives, directives, status, priority, tags, created_at, updated_at")
    .eq("id", id)
    .eq("user_id", userId)
    .maybeSingle()

  if (!op) notFound()

  const [{ data: records }, { data: briefs }] = await Promise.all([
    supabase
      .from("operation_records")
      .select("id, title, content, type, status, priority, created_at, updated_at")
      .eq("operation_id", id)
      .order("created_at", { ascending: false })
      .limit(100),
    supabase
      .from("operation_briefs")
      .select("id, kind, content, generated_at")
      .eq("operation_id", id)
      .order("generated_at", { ascending: false })
      .limit(20),
  ])

  return (
    <main className="min-h-screen px-4 sm:px-6 md:px-10 py-8 max-w-5xl mx-auto">
      <Link
        href="/dashboard/operations"
        className="inline-flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground mb-6"
      >
        <ChevronLeft size={14} /> All operations
      </Link>

      <OperationDetailClient
        operation={op as never}
        records={(records ?? []) as never}
        briefs={(briefs ?? []) as never}
      />
    </main>
  )
}
