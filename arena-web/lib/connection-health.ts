import { getServiceClient } from "@/lib/supabase/service"
import { sendConnectionErrorEmail } from "@/lib/email/sendConnectionError"

// Connection health bookkeeping.
//
// Every executor route (task/create, task/update, payment/route) calls
// `recordConnectionResult` after talking to the provider. Successful calls
// bump `last_used_at` and clear any prior error. Failed calls update
// `last_error`; when the error looks auth-related we flip the row to
// `status='errored'` so the dashboard can warn the user before they hit
// the next failure silently.
//
// Idempotent + best-effort: bookkeeping never blocks the executor response.

export type ConnectionResult =
  | { ok: true }
  | { ok: false; error: string }

const AUTH_ERROR_PATTERNS = [
  /401/i,
  /403/i,
  /unauthor[ie]z/i,         // "unauthorized" or "unauthorised"
  /invalid_auth/i,
  /token.*(rejected|expired|invalid|revoked)/i,
  /(rejected|expired|invalid|revoked).*token/i,
  /authentication.*fail/i,
  /forbidden/i,
]

function looksLikeAuthError(msg: string): boolean {
  return AUTH_ERROR_PATTERNS.some((re) => re.test(msg))
}

/// Throttle: don't send a fresh notification email if we already sent one
/// in the last 24h. Stops a flaky provider (network blip → cycle → notify
/// → cycle → notify) from spamming the user.
const NOTIFICATION_COOLDOWN_MS = 24 * 60 * 60 * 1000

export async function recordConnectionResult(
  connectionId: string,
  result: ConnectionResult,
): Promise<void> {
  const supabase = getServiceClient()
  try {
    if (result.ok) {
      // Successful call — clear errored state + reset notification throttle
      // so the next failure sends a fresh email (this isn't a "flapping"
      // provider, the user fixed it).
      await supabase
        .from("arena_connections")
        .update({
          status: "active",
          last_used_at: new Date().toISOString(),
          last_error: null,
          error_notified_at: null,
        })
        .eq("id", connectionId)
    } else {
      const isAuth = looksLikeAuthError(result.error)
      const update: Record<string, unknown> = {
        last_used_at: new Date().toISOString(),
        last_error: result.error.slice(0, 500),
      }
      if (isAuth) update.status = "errored"

      await supabase
        .from("arena_connections")
        .update(update)
        .eq("id", connectionId)

      // Only notify on auth errors — transient HTTP 500s don't need an
      // email. Throttle by error_notified_at so we don't spam.
      if (isAuth) {
        await maybeNotifyConnectionError(connectionId, result.error)
      }
    }
  } catch {
    // Bookkeeping errors are silently swallowed — they must never block
    // the executor response. The next call will try to update the row again.
  }
}

/// Send the connection-error email if it's been long enough since the
/// last one (or there's never been one). Best-effort; failure is fine.
async function maybeNotifyConnectionError(connectionId: string, errorReason: string): Promise<void> {
  const supabase = getServiceClient()

  // Pull the connection + its owner's email + display name in one go.
  // We need: provider, label, error_notified_at (throttle), and the
  // human's email/display_name to address the message.
  const { data } = await supabase
    .from("arena_connections")
    .select(`
      id, provider, label, error_notified_at, user_id,
      user:user_id ( email )
    `)
    .eq("id", connectionId)
    .single()

  if (!data) return

  // Throttle check
  if (data.error_notified_at) {
    const last = new Date(data.error_notified_at).getTime()
    if (Date.now() - last < NOTIFICATION_COOLDOWN_MS) return
  }

  // Resolve recipient. The PostgREST joined `user` is auth.users which
  // gives us email; for display name we cross to humans by auth_id.
  const userEmail = (data.user as any)?.email as string | undefined
  if (!userEmail) return

  const { data: human } = await supabase
    .from("humans")
    .select("display_name")
    .eq("auth_id", data.user_id)
    .maybeSingle()
  const recipientName = (human?.display_name as string | undefined)?.split(/\s+/)[0] || "there"

  const result = await sendConnectionErrorEmail({
    to: userEmail,
    recipientName,
    provider: data.provider as string,
    connectionLabel: (data.label as string | null) ?? null,
    errorReason,
    connectionId,
  })

  // Stamp the throttle so we don't re-send for a day. Stamp even when the
  // send failed (Resend unconfigured, etc.) so we don't retry on every
  // failed call — the user will see the error in the dashboard regardless.
  await supabase
    .from("arena_connections")
    .update({ error_notified_at: new Date().toISOString() })
    .eq("id", connectionId)

  if (!result.sent) {
    console.warn(`[arena] Connection error email not sent for ${connectionId}: ${result.reason}`)
  }
}
