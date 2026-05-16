// Push notification dispatch.
//
// Single entry point: `sendPush(humanId, event, payload)`. Looks up the
// human's registered devices, filters by per-event preferences, fires the
// platform-specific delivery (APNs today for iOS; web push / FCM are
// stubbed for later), and records each attempt in push_log.
//
// Why this lives in nexus-web (not a separate service): pretty much every
// event that wants to send a push is already happening in a route handler
// here (agent runs, schedule firings, research completions). One module
// import is simpler than a side-channel queue.
//
// Provider config:
//   APNS_TEAM_ID     — Apple Developer team ID (10-char string)
//   APNS_KEY_ID      — APNs auth key ID
//   APNS_KEY_PEM     — auth key contents (PEM, the .p8 file as a string)
//   APNS_TOPIC       — bundle id, e.g. "com.maxwell.nexus-ios"
//   APNS_USE_SANDBOX — "1" to send to sandbox gateway (development builds)
//
// Without these envs, sendPush() runs through the lookup + log paths but
// marks every attempt status='skipped' / reason='APNS_NOT_CONFIGURED'.
// That way the data trail is consistent whether or not Patrick has wired
// the cert — we can audit what WOULD have fired and turn delivery on
// later by just adding the env vars to Vercel.

import { createClient } from "@supabase/supabase-js"
import crypto from "crypto"

export type PushEvent =
  | "agent.done"
  | "schedule.fired"
  | "research.done"
  | "op.updated"
  | "terminal.alert"

export interface PushPayload {
  title: string
  body: string
  // Deep-link target on iOS. Routes through the iOS NotificationCenter
  // delegate (when we add one in nexus-iosApp) to open the right tab.
  // Examples: "nexus://operations/<id>", "nexus://terminals/<id>".
  link?: string
  // Free-form extra payload that lands in `userInfo` on iOS. Kept small —
  // APNs payload cap is 4KB.
  extra?: Record<string, unknown>
}

interface DeviceRow {
  id: string
  human_id: string
  platform: string
  token: string
  bundle_id: string | null
  notify_agent_done: boolean
  notify_schedule_fired: boolean
  notify_research_done: boolean
  notify_op_updated: boolean
  notify_terminal_alert: boolean
  consecutive_failures: number
}

function getServiceClient() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { persistSession: false, autoRefreshToken: false } }
  )
}

/// Map event → the boolean column on push_devices that gates it.
function prefColumnFor(event: PushEvent): keyof DeviceRow {
  switch (event) {
    case "agent.done":      return "notify_agent_done"
    case "schedule.fired":  return "notify_schedule_fired"
    case "research.done":   return "notify_research_done"
    case "op.updated":      return "notify_op_updated"
    case "terminal.alert":  return "notify_terminal_alert"
  }
}

/// Resolve `auth.users.id` → `humans.id`. Cron-fired dispatchers carry the
/// user-id of who owns the schedule; that's the auth_id, not the human_id.
/// Returns null when there's no matching humans row (shouldn't happen for
/// fully-onboarded users, but stay defensive).
export async function humanIdFromAuthId(authId: string): Promise<string | null> {
  const supabase = getServiceClient()
  const { data } = await supabase
    .from("humans")
    .select("id")
    .eq("auth_id", authId)
    .maybeSingle()
  return (data?.id as string | undefined) ?? null
}

/// Convenience wrapper for cron/dispatch paths that only have auth_id.
/// Same return shape as sendPush; on missing humans row returns zeros.
export async function sendPushToAuthUser(
  authId: string,
  event: PushEvent,
  payload: PushPayload,
): Promise<{ sent: number; skipped: number; failed: number }> {
  const humanId = await humanIdFromAuthId(authId)
  if (!humanId) return { sent: 0, skipped: 0, failed: 0 }
  return sendPush(humanId, event, payload)
}

/// Public entry point. Returns counts so callers can log dispatch outcomes.
export async function sendPush(
  humanId: string,
  event: PushEvent,
  payload: PushPayload,
): Promise<{ sent: number; skipped: number; failed: number }> {
  const supabase = getServiceClient()
  const { data: rows } = await supabase
    .from("push_devices")
    .select("id, human_id, platform, token, bundle_id, notify_agent_done, notify_schedule_fired, notify_research_done, notify_op_updated, notify_terminal_alert, consecutive_failures")
    .eq("human_id", humanId)
    .returns<DeviceRow[]>()

  const devices = rows ?? []
  if (devices.length === 0) {
    await recordLog({ humanId, deviceId: null, event, payload, status: "skipped", reason: "NO_DEVICES" })
    return { sent: 0, skipped: 1, failed: 0 }
  }

  let sent = 0, skipped = 0, failed = 0
  for (const d of devices) {
    const prefCol = prefColumnFor(event)
    if (d[prefCol] === false) {
      await recordLog({ humanId, deviceId: d.id, event, payload, status: "skipped", reason: "USER_PREF_OFF" })
      skipped += 1
      continue
    }
    const outcome = await deliver(d, event, payload)
    await recordLog({
      humanId, deviceId: d.id, event, payload,
      status: outcome.ok ? "sent" : (outcome.skip ? "skipped" : "failed"),
      reason: outcome.reason ?? null,
    })
    await updateDeviceBookkeeping(d, outcome)
    if (outcome.ok) sent += 1
    else if (outcome.skip) skipped += 1
    else failed += 1
  }

  return { sent, skipped, failed }
}

type DeliveryResult =
  | { ok: true; skip?: false; reason?: string }
  | { ok: false; skip: true; reason: string }     // configured-off / not-our-platform
  | { ok: false; skip?: false; reason: string }   // real failure (auth, network, bad token)

async function deliver(d: DeviceRow, event: PushEvent, payload: PushPayload): Promise<DeliveryResult> {
  if (d.platform === "ios" || d.platform === "macos") {
    return deliverAPNs(d, event, payload)
  }
  // Other platforms are placeholders so we don't silently swallow rows.
  return { ok: false, skip: true, reason: `PLATFORM_NOT_IMPLEMENTED:${d.platform}` }
}

// MARK: - APNs (HTTP/2 + JWT)

interface APNsConfig {
  teamId: string
  keyId: string
  keyPem: string
  topicDefault: string
  useSandbox: boolean
}

function loadAPNsConfig(): APNsConfig | { error: string } {
  const teamId = process.env.APNS_TEAM_ID
  const keyId  = process.env.APNS_KEY_ID
  const keyPem = process.env.APNS_KEY_PEM
  const topic  = process.env.APNS_TOPIC
  if (!teamId || !keyId || !keyPem || !topic) return { error: "APNS_NOT_CONFIGURED" }
  return {
    teamId, keyId,
    keyPem: keyPem.replace(/\\n/g, "\n"),  // Vercel envs collapse newlines
    topicDefault: topic,
    useSandbox: process.env.APNS_USE_SANDBOX === "1",
  }
}

// Token cache. JWTs are valid up to 60 min; we refresh at 45 min to be safe.
let cachedJwt: { token: string; expiresAt: number } | null = null

function getAPNsJWT(cfg: APNsConfig): string {
  const now = Math.floor(Date.now() / 1000)
  if (cachedJwt && cachedJwt.expiresAt > now + 60) return cachedJwt.token
  const header = base64UrlEncode(JSON.stringify({ alg: "ES256", kid: cfg.keyId }))
  const payload = base64UrlEncode(JSON.stringify({ iss: cfg.teamId, iat: now }))
  const signingInput = `${header}.${payload}`
  const sign = crypto.createSign("SHA256")
  sign.update(signingInput)
  // ES256 — output DER, convert to raw r||s.
  const derSignature = sign.sign({ key: cfg.keyPem, dsaEncoding: "ieee-p1363" })
  const sig = base64UrlEncode(derSignature)
  const token = `${signingInput}.${sig}`
  cachedJwt = { token, expiresAt: now + 45 * 60 }
  return token
}

function base64UrlEncode(input: string | Buffer): string {
  const buf = typeof input === "string" ? Buffer.from(input) : input
  return buf.toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}

async function deliverAPNs(d: DeviceRow, event: PushEvent, payload: PushPayload): Promise<DeliveryResult> {
  const cfg = loadAPNsConfig()
  if ("error" in cfg) return { ok: false, skip: true, reason: cfg.error }

  const topic = d.bundle_id || cfg.topicDefault
  const host = cfg.useSandbox ? "api.sandbox.push.apple.com" : "api.push.apple.com"
  const url = `https://${host}/3/device/${d.token}`

  const body = JSON.stringify({
    aps: {
      alert: { title: payload.title, body: payload.body },
      sound: "default",
      "thread-id": event,
    },
    nexusEvent: event,
    link: payload.link ?? null,
    extra: payload.extra ?? null,
  })

  try {
    const res = await fetch(url, {
      method: "POST",
      headers: {
        authorization: `bearer ${getAPNsJWT(cfg)}`,
        "apns-topic": topic,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "content-type": "application/json",
      },
      body,
    })
    if (res.status === 200) return { ok: true }
    const errBody = await res.text().catch(() => "")
    // 410 means the device token is dead (user uninstalled / reset).
    // 400 + BadDeviceToken / Unregistered = same outcome. Either way we
    // should stop sending to this row.
    const fatal = res.status === 410 || /BadDeviceToken|Unregistered/.test(errBody)
    return { ok: false, skip: false, reason: `APNS_${res.status}:${errBody.slice(0, 200)}${fatal ? " (token dead)" : ""}` }
  } catch (e: any) {
    return { ok: false, skip: false, reason: `APNS_NETWORK:${e?.message ?? String(e)}` }
  }
}

// MARK: - Logging / bookkeeping

async function recordLog(opts: {
  humanId: string
  deviceId: string | null
  event: PushEvent
  payload: PushPayload
  status: "sent" | "skipped" | "failed"
  reason: string | null
}) {
  const supabase = getServiceClient()
  await supabase.from("push_log").insert({
    device_id: opts.deviceId,
    human_id: opts.humanId,
    event: opts.event,
    title: opts.payload.title,
    body: opts.payload.body,
    payload: { link: opts.payload.link ?? null, extra: opts.payload.extra ?? null },
    status: opts.status,
    status_reason: opts.reason,
  })
}

const FAILURE_PRUNE_THRESHOLD = 10

async function updateDeviceBookkeeping(d: DeviceRow, outcome: DeliveryResult) {
  const supabase = getServiceClient()
  if (outcome.ok) {
    await supabase
      .from("push_devices")
      .update({
        last_sent_at: new Date().toISOString(),
        last_seen_at: new Date().toISOString(),
        consecutive_failures: 0,
        last_error: null,
      })
      .eq("id", d.id)
    return
  }
  if (outcome.skip) {
    // Don't penalize the row for "platform not implemented" / "config off."
    return
  }
  const fatal = /token dead|Unregistered|BadDeviceToken|APNS_410/.test(outcome.reason)
  const nextFailures = d.consecutive_failures + 1
  if (fatal || nextFailures >= FAILURE_PRUNE_THRESHOLD) {
    await supabase.from("push_devices").delete().eq("id", d.id)
    return
  }
  await supabase
    .from("push_devices")
    .update({
      consecutive_failures: nextFailures,
      last_error: outcome.reason.slice(0, 500),
    })
    .eq("id", d.id)
}
