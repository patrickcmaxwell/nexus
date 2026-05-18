// POST /api/admin/delete-human
//
// Hard-delete a human row. This is intentionally more dangerous than
// lock-user (which just flips status=disabled). Use when the human was
// added in error, OR the person genuinely needs to be removed from the
// workspace permanently.
//
// What happens on delete:
//   - humans row removed
//   - cascading deletes on FK'd tables fire automatically per their ON
//     DELETE rules (push_devices CASCADE, terminal_watch_state CASCADE)
//   - sessions referencing this human are invalidated explicitly first
//     so any in-flight request doesn't accidentally outlive the row
//
// What does NOT cascade and stays in place:
//   - eve_history / eve_conversations / operations / agents — these
//     reference auth.users.id, not humans.id. Their content (Patrick's
//     ops, Eve's memory of conversations with this person) survives.
//   - security_log entries — audit trail must not be auto-erased.
//
// Body: { targetHumanId: string, confirmDisplayName: string }
//
// We require the caller to echo back the target's display_name as a
// type-to-confirm guard. Pure ID-based delete is too easy to fat-finger
// when the UI bundles it next to lock/reset buttons.
//
// Guardrails:
//   - Caller must be admin OR owner
//   - Cannot delete the owner (root of trust)
//   - Cannot delete yourself (would brick your own session mid-request)
//   - Confirm name must match (case-insensitive trim)
import { NextRequest, NextResponse } from "next/server"
import { requireAdmin, getServiceClient, logAdminAction } from "@/lib/auth/admin"

export async function POST(req: NextRequest) {
  const gate = await requireAdmin()
  if ("error" in gate) return gate.error
  const { admin } = gate

  const { targetHumanId, confirmDisplayName } = await req.json().catch(() => ({}))
  if (!targetHumanId) {
    return NextResponse.json({ error: "targetHumanId is required" }, { status: 400 })
  }
  if (targetHumanId === admin.humanId) {
    return NextResponse.json(
      { error: "Cannot delete yourself" },
      { status: 400 }
    )
  }

  const supabase = getServiceClient()
  const { data: target } = await supabase
    .from("humans")
    .select("id, display_name, email, role, is_owner, status")
    .eq("id", targetHumanId)
    .single()

  if (!target) {
    return NextResponse.json({ error: "Target user not found" }, { status: 404 })
  }
  if (target.is_owner) {
    return NextResponse.json({ error: "Cannot delete the owner" }, { status: 403 })
  }

  const expected = (target.display_name ?? "").trim().toLowerCase()
  const provided = (confirmDisplayName ?? "").trim().toLowerCase()
  if (!expected || expected !== provided) {
    return NextResponse.json(
      { error: `Confirm by typing the user's display name exactly ("${target.display_name}")` },
      { status: 400 }
    )
  }

  // Best-effort invalidate sessions BEFORE deleting, so any in-flight
  // request from this human returns 401 instead of 500-ing on a missing
  // FK target.
  await supabase
    .from("security_sessions")
    .update({ invalidated: true })
    .eq("team_member_id", targetHumanId)

  const { error: deleteErr } = await supabase
    .from("humans")
    .delete()
    .eq("id", targetHumanId)

  if (deleteErr) {
    return NextResponse.json({ error: deleteErr.message }, { status: 500 })
  }

  await logAdminAction({
    event: "admin.delete_human",
    actorHumanId: admin.humanId,
    actorDisplayName: admin.displayName,
    // No targetHumanId on the log row's user_id — the human row is gone,
    // FK would be NULL anyway. We keep the id in metadata for forensics.
    metadata: {
      deletedHumanId: targetHumanId,
      targetDisplayName: target.display_name,
      targetEmail: target.email,
      previousStatus: target.status,
    },
  })

  return NextResponse.json({
    success: true,
    deletedDisplayName: target.display_name,
  })
}
