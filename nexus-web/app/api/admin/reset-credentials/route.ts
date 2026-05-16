// POST /api/admin/reset-credentials
//
// Issue a fresh invite token for an existing human. Their status flips to
// 'invited' and all current sessions are invalidated. They go through
// /invite/[token] again to set a new PIN + face descriptor — same flow
// as initial onboarding.
//
// Use cases:
//   - Forgotten PIN (admin-side recovery; for self-recovery the user can
//     hit /api/auth/change-pin if they still know their current PIN)
//   - Suspected compromise (lock first, then reset)
//   - Restoring a previously-locked user (status=disabled → invited)
//
// Body: { targetHumanId: string, reason?: string }
//
// Guardrails:
//   - Caller must be admin OR owner
//   - Cannot reset the owner — owner self-recovery is a separate flow
//     (recovery codes / trusted contacts, not yet built)
//   - Cannot reset yourself — use /api/auth/change-pin while logged in
import { NextRequest, NextResponse } from "next/server"
import { requireAdmin, getServiceClient, logAdminAction } from "@/lib/auth/admin"
import { publicOrigin } from "@/lib/auth/origin"
import crypto from "crypto"

export async function POST(req: NextRequest) {
  const gate = await requireAdmin()
  if ("error" in gate) return gate.error
  const { admin } = gate

  const { targetHumanId, reason } = await req.json()
  if (!targetHumanId) {
    return NextResponse.json({ error: "targetHumanId is required" }, { status: 400 })
  }
  if (targetHumanId === admin.humanId) {
    return NextResponse.json(
      { error: "Cannot reset your own credentials — use Change PIN instead" },
      { status: 400 }
    )
  }

  const supabase = getServiceClient()
  const { data: target } = await supabase
    .from("humans")
    .select("id, display_name, email, is_owner, status")
    .eq("id", targetHumanId)
    .single()

  if (!target) {
    return NextResponse.json({ error: "Target user not found" }, { status: 404 })
  }
  if (target.is_owner) {
    return NextResponse.json({ error: "Cannot reset the owner" }, { status: 403 })
  }

  // Generate new invite token. Status goes to 'invited' so the user goes
  // through the same /invite/[token] onboarding flow as a new hire.
  const inviteToken = crypto.randomBytes(32).toString("hex")

  await supabase
    .from("humans")
    .update({
      invite_token: inviteToken,
      status: "invited",
    })
    .eq("id", targetHumanId)

  await supabase
    .from("security_sessions")
    .update({ invalidated: true })
    .eq("team_member_id", targetHumanId)

  const inviteUrl = `${publicOrigin(req)}/invite/${inviteToken}`

  await logAdminAction({
    event: "admin.reset_credentials",
    actorHumanId: admin.humanId,
    actorDisplayName: admin.displayName,
    targetHumanId,
    metadata: {
      targetDisplayName: target.display_name,
      previousStatus: target.status,
      reason: reason ?? null,
    },
  })

  return NextResponse.json({
    success: true,
    targetDisplayName: target.display_name,
    targetEmail: target.email,
    inviteUrl,
  })
}
