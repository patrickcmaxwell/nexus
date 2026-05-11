// Slack OAuth v2 helpers.
//
// Bot scopes we request: chat:write (post messages), channels:read +
// groups:read (list channels for the picker). Token format: xoxb-* bot
// tokens, used as Bearer.
//
// Reference: https://docs.slack.dev/authentication/installing-with-oauth

import crypto from "node:crypto"

export const SLACK_AUTHORIZE_URL = "https://slack.com/oauth/v2/authorize"
export const SLACK_TOKEN_URL     = "https://slack.com/api/oauth.v2.access"
export const SLACK_API_BASE      = "https://slack.com/api"
export const SLACK_BOT_SCOPES    = "chat:write,chat:write.public,channels:read,groups:read"

export const SLACK_OAUTH_STATE_COOKIE  = "arena_slack_oauth_state"
export const SLACK_OAUTH_STATE_TTL_SEC = 600

export type SlackStatePayload = { nonce: string; userId: string; iat: number }

export function mintState(opts: { userId: string }): { nonce: string; cookieValue: string } {
  const nonce = crypto.randomBytes(24).toString("hex")
  const payload: SlackStatePayload = {
    nonce, userId: opts.userId, iat: Math.floor(Date.now() / 1000),
  }
  const secret = process.env.OAUTH_STATE_SECRET || process.env.CRON_SECRET || "dev-only-secret"
  const body = Buffer.from(JSON.stringify(payload)).toString("base64url")
  const sig = crypto.createHmac("sha256", secret).update(body).digest("base64url")
  return { nonce, cookieValue: `${body}.${sig}` }
}

export function verifyState(cookieValue: string | undefined, returnedNonce: string): SlackStatePayload | null {
  if (!cookieValue || !returnedNonce) return null
  const [body, sig] = cookieValue.split(".")
  if (!body || !sig) return null
  const secret = process.env.OAUTH_STATE_SECRET || process.env.CRON_SECRET || "dev-only-secret"
  const expected = crypto.createHmac("sha256", secret).update(body).digest("base64url")
  if (sig !== expected) return null
  let payload: SlackStatePayload
  try { payload = JSON.parse(Buffer.from(body, "base64url").toString("utf8")) }
  catch { return null }
  if (payload.nonce !== returnedNonce) return null
  if (Date.now() / 1000 - payload.iat > SLACK_OAUTH_STATE_TTL_SEC) return null
  return payload
}

export function buildAuthorizeUrl(opts: {
  clientId: string
  redirectUri: string
  state: string
}): string {
  const u = new URL(SLACK_AUTHORIZE_URL)
  u.searchParams.set("client_id", opts.clientId)
  u.searchParams.set("scope", SLACK_BOT_SCOPES)
  u.searchParams.set("redirect_uri", opts.redirectUri)
  u.searchParams.set("state", opts.state)
  return u.toString()
}

export type SlackTokenResult = {
  accessToken: string  // xoxb-*
  scope: string
  botUserId: string
  appId: string
  teamId: string
  teamName: string
  authedUserId: string | null
}

export async function exchangeCodeForToken(opts: {
  clientId: string
  clientSecret: string
  code: string
  redirectUri: string
}): Promise<SlackTokenResult> {
  const body = new URLSearchParams({
    code: opts.code,
    client_id: opts.clientId,
    client_secret: opts.clientSecret,
    redirect_uri: opts.redirectUri,
  })
  const res = await fetch(SLACK_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: body.toString(),
  })
  if (!res.ok) {
    const detail = await res.text().catch(() => `HTTP ${res.status}`)
    throw new Error(`Slack token exchange failed: ${detail.slice(0, 300)}`)
  }
  // Slack always returns 200 even on errors; check `ok` field.
  const json = await res.json() as {
    ok: boolean
    error?: string
    access_token?: string
    scope?: string
    bot_user_id?: string
    app_id?: string
    team?: { id: string; name: string }
    authed_user?: { id: string }
  }
  if (!json.ok || !json.access_token || !json.team) {
    throw new Error(`Slack token exchange returned error: ${json.error ?? JSON.stringify(json).slice(0, 200)}`)
  }
  return {
    accessToken:  json.access_token,
    scope:        json.scope ?? "",
    botUserId:    json.bot_user_id ?? "",
    appId:        json.app_id ?? "",
    teamId:       json.team.id,
    teamName:     json.team.name,
    authedUserId: json.authed_user?.id ?? null,
  }
}

/// List channels (public + private the bot was added to) for the picker.
export async function listChannels(accessToken: string): Promise<Array<{ id: string; name: string; is_private: boolean }>> {
  const u = new URL(`${SLACK_API_BASE}/conversations.list`)
  u.searchParams.set("limit", "200")
  u.searchParams.set("exclude_archived", "true")
  u.searchParams.set("types", "public_channel,private_channel")
  const res = await fetch(u.toString(), {
    headers: { Authorization: `Bearer ${accessToken}` },
  })
  if (!res.ok) throw new Error(`Slack conversations.list failed: HTTP ${res.status}`)
  const json = await res.json() as {
    ok: boolean
    error?: string
    channels?: Array<{ id: string; name: string; is_private: boolean }>
  }
  if (!json.ok) throw new Error(`Slack: ${json.error ?? "unknown error"}`)
  return json.channels ?? []
}
