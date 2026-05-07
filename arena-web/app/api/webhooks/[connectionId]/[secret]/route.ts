import { NextRequest, NextResponse } from "next/server"
import { getServiceClient } from "@/lib/supabase/service"
import { writeAudit } from "@/lib/audit"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

// Generic inbound webhook receiver.
//
// URL shape: /api/webhooks/{connectionId}/{secret}
//
// The secret is per-connection (column `arena_connections.webhook_secret`),
// auto-generated on insert. Users paste the full URL into their provider's
// webhook settings. We verify connectionId + secret match a row, then drop
// the event into `arena_action_log` with action='inbound/<event>' and
// caller='webhook' so it shows up in the dashboard right alongside Eve's
// outbound calls.
//
// Per-provider HMAC signature verification is intentionally NOT here yet —
// the secret-in-path provides path-token auth (a stolen URL = stolen
// inbound channel, but the secret is per-connection and rotatable by
// re-creating the connection). When we add ClickUp/GitHub/Stripe-specific
// signature schemes they'll layer on top of this.

const MAX_BODY_BYTES = 512 * 1024  // 512KB cap — webhooks are small

export async function POST(
  req: NextRequest,
  { params }: { params: Promise<{ connectionId: string; secret: string }> },
) {
  const { connectionId, secret } = await params

  // Verify the secret matches the connection. Don't leak validity to randos
  // — return 200 in both branches so attackers can't use this endpoint as
  // a connection-existence oracle.
  const supabase = getServiceClient()
  const { data: connection } = await supabase
    .from("arena_connections")
    .select("id, provider, user_id, webhook_secret, status")
    .eq("id", connectionId)
    .maybeSingle()

  if (!connection || connection.webhook_secret !== secret) {
    // Quietly accept — no signal to scanners
    return NextResponse.json({ accepted: true })
  }

  // Read body (text first; we'll attempt JSON parse but tolerate non-JSON
  // since some providers send form-encoded or proprietary blobs).
  const raw = await req.text()
  if (raw.length > MAX_BODY_BYTES) {
    return NextResponse.json({ accepted: false, reason: "body too large" }, { status: 413 })
  }

  let body: unknown = raw
  try { body = JSON.parse(raw) } catch { /* keep as string */ }

  // Best-effort event type extraction. Each provider names this differently:
  //   Slack: { type, event: { type } } — top-level "type" usually 'event_callback'
  //   GitHub: X-GitHub-Event header is the source of truth
  //   ClickUp: { event: "taskCreated" }
  //   Stripe: { type: "charge.succeeded" }
  //   Notion: doesn't have official webhooks yet
  const eventType =
    req.headers.get("x-github-event") ||                         // GitHub
    (typeof body === "object" && body !== null
      ? (body as Record<string, unknown>).event
        || (body as Record<string, unknown>).type
        || (((body as Record<string, unknown>).event_type as string | undefined))
      : undefined)
  const eventName = (typeof eventType === "string" ? eventType : "unknown").slice(0, 64)

  // Slack URL verification challenge. Slack sends a one-time POST with
  // type='url_verification' + challenge string when you save the webhook
  // URL in their UI. We must echo the challenge back as plain text.
  if (
    typeof body === "object" && body !== null
    && (body as Record<string, unknown>).type === "url_verification"
    && typeof (body as Record<string, unknown>).challenge === "string"
  ) {
    return new NextResponse((body as { challenge: string }).challenge, {
      status: 200,
      headers: { "content-type": "text/plain" },
    })
  }

  await writeAudit({
    action: `inbound/${connection.provider}/${eventName}`,
    caller: "system",  // 'webhook' isn't in the AuditCaller union yet — using 'system'
    payload: {
      provider: connection.provider,
      event: eventName,
      headers: pickHeaders(req),
      body,
    },
    status: "success",
  })

  return NextResponse.json({ accepted: true })
}

// Some providers (Stripe, notably) GET the webhook URL during setup to
// verify it returns 200. Same path-token check as POST.
export async function GET(
  _req: NextRequest,
  { params }: { params: Promise<{ connectionId: string; secret: string }> },
) {
  const { connectionId, secret } = await params
  const supabase = getServiceClient()
  const { data } = await supabase
    .from("arena_connections")
    .select("webhook_secret")
    .eq("id", connectionId)
    .maybeSingle()
  if (!data || data.webhook_secret !== secret) {
    return NextResponse.json({ accepted: true })
  }
  return NextResponse.json({ ok: true, ready: true })
}

function pickHeaders(req: NextRequest): Record<string, string> {
  // Preserve the per-provider signature/event headers for debugging and
  // future signature verification. Don't preserve everything (cookies
  // could leak; size could explode).
  const keep = [
    "x-github-event",
    "x-github-delivery",
    "x-hub-signature-256",
    "x-slack-signature",
    "x-slack-request-timestamp",
    "stripe-signature",
    "x-clickup-signature",
    "user-agent",
    "content-type",
  ]
  const out: Record<string, string> = {}
  for (const k of keep) {
    const v = req.headers.get(k)
    if (v) out[k] = v.slice(0, 500)
  }
  return out
}
