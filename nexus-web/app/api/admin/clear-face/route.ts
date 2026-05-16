// POST /api/admin/clear-face
//
// Wipe a target human's stored face descriptors so they can re-enroll a face
// without a full credential reset. PIN stays untouched. Use when the stored
// face has drifted (haircut, glasses, etc) to the point that nothing matches
// and the user still knows their PIN.
//
// Body: { targetHumanId: string, reason?: string }
//
// Guardrails:
//   - Caller must be admin OR owner
//   - Cannot clear the owner's face (root-of-trust)
//   - Cannot clear your own face here — use Settings → Update face photo
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
    return NextResponse.json(
      { error: "Use Settings → Update face photo to change your own face" },
      { status: 400 }
    )
  }

  const supabase = getServiceClient()
  const { data: target } = await supabase
    .from("humans")
    .select("id, display_name, is_owner")
    .eq("id", targetHumanId)
    .single()

  if (!target) {
    return NextResponse.json({ error: "Target user not found" }, { status: 404 })
  }
  if (target.is_owner) {
    return NextResponse.json({ error: "Cannot clear the owner's face data" }, { status: 403 })
  }

  await supabase
    .from("humans")
    .update({
      face_descriptors: null,
      face_descriptor: null,
      seed_face_descriptor: null,
    })
    .eq("id", targetHumanId)

  await logAdminAction({
    event: "admin.clear_face",
    actorHumanId: admin.humanId,
    actorDisplayName: admin.displayName,
    targetHumanId,
    metadata: {
      targetDisplayName: target.display_name,
      reason: reason ?? null,
    },
  })

  return NextResponse.json({ success: true, clearedFor: target.display_name })
}
