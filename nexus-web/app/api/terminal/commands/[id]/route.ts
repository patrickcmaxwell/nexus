// /api/terminal/commands/[id]
//
// Lumen marks a command as dispatched after feeding it into the PTY.
// If feeding failed (session terminated mid-poll, exec error), Lumen
// patches status='failed' with a failure_reason so iOS can surface it.
import { NextRequest, NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { getActiveAuthId } from "@/lib/auth/session"
import { checkDesktopAuth } from "@/lib/desktop-auth"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

const VALID_STATUS = new Set(["dispatched", "failed"])

export async function PATCH(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const userId = await getActiveAuthId()
  if (!userId || !(await checkDesktopAuth(req))) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }
  const { id } = await params
  const body = await req.json().catch(() => ({})) as {
    status?: string
    failure_reason?: string
  }
  if (!body.status || !VALID_STATUS.has(body.status)) {
    return NextResponse.json({ error: "status must be dispatched|failed" }, { status: 400 })
  }
  const patch: Record<string, unknown> = {
    status: body.status,
    dispatched_at: new Date().toISOString(),
  }
  if (body.failure_reason) patch.failure_reason = body.failure_reason

  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("terminal_commands")
    .update(patch)
    .eq("id", id)
    .eq("user_id", userId)
    .select("id, status, dispatched_at")
    .single()
  if (error || !data) {
    return NextResponse.json({ error: error?.message ?? "not found" }, { status: 404 })
  }
  return NextResponse.json(data)
}
