// POST /api/admin/unlock-user
//
// Flips a locked human's status back to 'active' without churning their PIN
// or face. The mirror of /api/admin/lock-user — use when an admin wants to
// restore a member who was disabled but did NOT lose their credentials.
//
// Body: { targetHumanId: string, reason?: string }
//
// Guardrails:
//   - Caller must be admin OR owner
//   - Cannot unlock yourself (you can't be locked AND signed in)
//   - Refuses if the row isn't currently 'disabled' — surfaces an error
//     instead of silently transitioning 'invited'→'active' (which would
//     skip PIN/face setup)
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
    return NextResponse.json({ error: "Cannot unlock yourself" }, { status: 400 })
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
  if (target.status === "invited") {
    return NextResponse.json(
      { error: "User hasn't completed onboarding — issue a reset link instead" },
      { status: 400 }
    )
  }
  if (target.status === "active") {
    return NextResponse.json(
      { error: "User is already active" },
      { status: 400 }
    )
  }

  await supabase.from("humans").update({ status: "active" }).eq("id", targetHumanId)

  await logAdminAction({
    event: "admin.unlock_user",
    actorHumanId: admin.humanId,
    actorDisplayName: admin.displayName,
    targetHumanId,
    metadata: {
      targetDisplayName: target.display_name,
      previousStatus: target.status,
      reason: reason ?? null,
    },
  })

  return NextResponse.json({ success: true, unlockedUser: target.display_name })
}
