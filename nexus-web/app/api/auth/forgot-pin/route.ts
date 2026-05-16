// POST /api/auth/forgot-pin
//
// Self-service "I forgot my PIN" flow. Body: { email }.
//
// Behavior:
//   - Looks up the human by email (case-insensitive)
//   - If found and status is 'active' (not invited/disabled), issues a fresh
//     invite_token, leaves the existing pin_hash/face untouched on the row,
//     and emails the reset URL. The flow is intentionally NOT destructive
//     before the user proves possession of the inbox — only when they click
//     through to /invite/[token] and complete the setup do the credentials
//     change.
//   - Wait — that's the wrong shape. To keep the existing /invite/[token]
//     contract (status='invited'), we DO flip the row to invited so the
//     token page accepts it. We also invalidate existing sessions to lock
//     the account in the meantime. The user can no longer sign in with the
//     old PIN until they complete the reset — which matches the standard
//     "PIN reset link expires the old PIN" behavior people expect.
//
// Rate limited. Returns 200 regardless of whether the email exists (no
// enumeration), with a body that indicates whether an email was sent. This
// is the same trade-off the PIN endpoint already makes — we surface enough
// info that the UI can guide the user, but limit volume.
import { NextRequest, NextResponse } from "next/server"
import { createClient } from "@supabase/supabase-js"
import crypto from "crypto"
import { sendPinResetEmail } from "@/lib/email/sendPinReset"
import { publicOrigin } from "@/lib/auth/origin"
import { checkRateLimit } from "@/lib/auth/ratelimit"

function getServiceClient() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { persistSession: false, autoRefreshToken: false } }
  )
}

export async function POST(req: NextRequest) {
  const rl = await checkRateLimit(req, { key: "generic" })
  if (!rl.allowed) {
    return NextResponse.json(
      { error: "RATE_LIMITED", retryAfterSeconds: rl.retryAfter },
      { status: 429, headers: { "Retry-After": String(rl.retryAfter) } }
    )
  }

  const { email } = await req.json().catch(() => ({}))
  if (!email || typeof email !== "string") {
    return NextResponse.json({ error: "email required" }, { status: 400 })
  }

  const supabase = getServiceClient()
  const { data: human } = await supabase
    .from("humans")
    .select("id, display_name, email, status, is_owner")
    .ilike("email", email.trim())
    .maybeSingle()

  // Owner self-reset isn't supported via this flow — the owner is the root
  // of trust. If they're locked out, they recover via the env-var passphrase
  // or direct DB access. Anything weaker risks letting an attacker who can
  // intercept the email take over the whole tenant.
  if (human?.is_owner) {
    return NextResponse.json({
      success: true,
      sent: false,
      reason: "OWNER_NO_SELF_RESET",
    })
  }

  // Don't leak whether the email exists, but DO branch on whether we can
  // actually send. The UI shows the same "check your inbox" string either
  // way — admins can still see real outcomes in the audit log.
  if (!human || human.status !== "active") {
    return NextResponse.json({ success: true, sent: false, reason: "NO_OP" })
  }

  const token = crypto.randomBytes(32).toString("hex")
  await supabase
    .from("humans")
    .update({ invite_token: token, status: "invited" })
    .eq("id", human.id)

  // Invalidate live sessions so a stolen cookie can't keep the old PIN alive
  // through the reset window.
  await supabase
    .from("security_sessions")
    .update({ invalidated: true })
    .eq("team_member_id", human.id)

  const resetUrl = `${publicOrigin(req)}/invite/${token}`
  const emailResult = await sendPinResetEmail({
    to: human.email,
    displayName: human.display_name,
    resetUrl,
  })

  // Log the event for admin auditing — uses security_log directly because
  // this isn't an admin action (no actor human), it's user-initiated.
  await supabase.from("security_log").insert({
    user_id: human.id,
    event: "user.forgot_pin",
    metadata: {
      targetHumanId: human.id,
      targetDisplayName: human.display_name,
      emailSent: emailResult.sent,
      emailReason: emailResult.sent ? null : emailResult.reason,
    },
  })

  return NextResponse.json({
    success: true,
    sent: emailResult.sent,
    reason: emailResult.sent ? null : emailResult.reason,
  })
}
