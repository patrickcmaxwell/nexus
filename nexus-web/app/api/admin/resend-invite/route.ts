// POST /api/admin/resend-invite
//
// Re-email the invite link for a human who's still in 'invited' status.
// Cheap and non-destructive — the existing invite_token, PIN setup, and
// face descriptors are all left alone. If the user lost the original email,
// this gets them back in without forcing a full credential reset.
//
// Body: { targetHumanId: string, rotate?: boolean }
//
// `rotate: true` regenerates the token before re-sending. Use when the
// original link has been shared somewhere risky or you just want to be
// safe. Default behavior (rotate omitted) reuses the existing token.
//
// Guardrails:
//   - Caller must be admin OR owner
//   - Target must be in status='invited' (active/disabled users go through
//     reset-credentials instead — that's the more destructive path)
//   - Cannot resend to the owner (root of trust)
import { NextRequest, NextResponse } from "next/server"
import { requireAdmin, getServiceClient, logAdminAction } from "@/lib/auth/admin"
import { publicOrigin } from "@/lib/auth/origin"
import { sendInviteEmail } from "@/lib/email/sendInvite"
import crypto from "crypto"

export async function POST(req: NextRequest) {
  const gate = await requireAdmin()
  if ("error" in gate) return gate.error
  const { admin } = gate

  const { targetHumanId, rotate } = await req.json().catch(() => ({}))
  if (!targetHumanId) {
    return NextResponse.json({ error: "targetHumanId is required" }, { status: 400 })
  }

  const supabase = getServiceClient()
  const { data: target } = await supabase
    .from("humans")
    .select("id, display_name, email, role, status, is_owner, invite_token")
    .eq("id", targetHumanId)
    .single()

  if (!target) {
    return NextResponse.json({ error: "Target user not found" }, { status: 404 })
  }
  if (target.is_owner) {
    return NextResponse.json({ error: "Cannot resend invite to the owner" }, { status: 403 })
  }
  if (target.status !== "invited") {
    return NextResponse.json(
      { error: `User is ${target.status}, not 'invited' — use Reset PIN + face instead` },
      { status: 400 }
    )
  }

  // Rotate the token when asked, or when the row somehow lost it (defensive
  // — shouldn't happen, but if it does we'd rather mint a new one than
  // 500 on a NULL invite_url).
  let inviteToken = target.invite_token as string | null
  if (rotate || !inviteToken) {
    inviteToken = crypto.randomBytes(32).toString("hex")
    await supabase
      .from("humans")
      .update({ invite_token: inviteToken })
      .eq("id", targetHumanId)
  }

  const inviteUrl = `${publicOrigin(req)}/invite/${inviteToken}`
  const emailResult = await sendInviteEmail({
    to: target.email,
    inviteeName: target.display_name,
    inviterName: admin.displayName,
    inviterEmail: admin.email,
    inviteUrl,
    role: target.role ?? "observer",
  })

  await logAdminAction({
    event: "admin.resend_invite",
    actorHumanId: admin.humanId,
    actorDisplayName: admin.displayName,
    targetHumanId,
    metadata: {
      targetDisplayName: target.display_name,
      rotated: !!rotate || !target.invite_token,
      emailSent: emailResult.sent,
      emailReason: emailResult.sent ? null : emailResult.reason,
    },
  })

  return NextResponse.json({
    success: true,
    targetDisplayName: target.display_name,
    inviteUrl,
    rotated: !!rotate || !target.invite_token,
    email: emailResult.sent
      ? { sent: true, id: emailResult.id }
      : { sent: false, reason: emailResult.reason },
  })
}
