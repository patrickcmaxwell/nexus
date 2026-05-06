// POST /api/admin/lock-user
//
// Lock a target human's account: invalidates every session they hold and
// flips their status to 'disabled' so they can't authenticate again until
// an admin restores them via reset-credentials.
//
// Body: { targetHumanId: string, reason?: string }
//
// Guardrails:
//   - Caller must be admin OR owner (requireAdmin)
//   - Cannot lock the owner — the owner is the root of trust and only
//     they can self-disable via signOut. This prevents a compromised
//     admin from locking the owner out.
//   - Cannot lock yourself (would brick your own session). Use signOut.
import { NextRequest, NextResponse } from "next/server"
import { requireAdmin, getServiceClient, logAdminAction } from "@/lib/auth/admin"

export async function POST(req: NextRequest) {
  const gate = await requireAdmin()
  if ("error" in gate) return gate.error
  const { admin } = gate

  const { targetHumanId, reason } = await req.json()
  if (!targetHumanId) {
    return NextResponse.json({ error: "targetHumanId is required" }, { status: 400 })
  }
  if (targetHumanId === admin.humanId) {
    return NextResponse.json({ error: "Cannot lock your own account — use Sign Out" }, { status: 400 })
  }

  const supabase = getServiceClient()
  const { data: target } = await supabase
    .from("humans")
    .select("id, display_name, is_owner, status")
    .eq("id", targetHumanId)
    .single()

  if (!target) {
    return NextResponse.json({ error: "Target user not found" }, { status: 404 })
  }
  if (target.is_owner) {
    return NextResponse.json({ error: "Cannot lock the owner" }, { status: 403 })
  }

  // Invalidate every session the target holds, then flip status.
  await supabase
    .from("security_sessions")
    .update({ invalidated: true })
    .eq("team_member_id", targetHumanId)

  await supabase
    .from("humans")
    .update({ status: "disabled" })
    .eq("id", targetHumanId)

  await logAdminAction({
    event: "admin.lock_user",
    actorHumanId: admin.humanId,
    actorDisplayName: admin.displayName,
    targetHumanId,
    metadata: {
      targetDisplayName: target.display_name,
      reason: reason ?? null,
    },
  })

  return NextResponse.json({ success: true, lockedUser: target.display_name })
}
