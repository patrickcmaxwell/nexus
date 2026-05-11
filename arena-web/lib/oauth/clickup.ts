// ClickUp OAuth helpers.
//
// Flow:
//   1. /api/oauth/clickup/start — set short-lived signed state cookie,
//      redirect user to ClickUp's consent screen
//   2. ClickUp authorizes → redirects user to our callback with `code` + `state`
//   3. /api/oauth/clickup/callback — verify state matches the cookie,
//      exchange code for an access_token, persist a connection, redirect
//      to the per-connection settings page
//
// ClickUp tokens are LONG-LIVED (no expiry, no refresh tokens). One token
// per connection is enough; rotate by re-authorizing.
//
// API docs: https://clickup.com/api/developer-portal/authentication/

import crypto from "node:crypto"

export const CLICKUP_AUTHORIZE_URL = "https://app.clickup.com/api"
export const CLICKUP_TOKEN_URL = "https://api.clickup.com/api/v2/oauth/token"
export const CLICKUP_API_BASE = "https://api.clickup.com/api/v2"

export const OAUTH_STATE_COOKIE = "arena_oauth_state"
export const OAUTH_STATE_TTL_SEC = 600  // 10 minutes

export type OauthStatePayload = {
  /** Random nonce — what the upstream provider echoes back. */
  nonce: string
  /** Authoring user (humans.auth_id) — the row owner on success. */
  userId: string
  /** Where to send the user after a successful exchange. */
  returnTo?: string
  /** Issued-at unix seconds, used for TTL check on callback. */
  iat: number
}

/// Mint a fresh state token (random) and return both halves: the nonce
/// (sent to ClickUp + echoed back as `state`) and the JSON payload that
/// goes in the cookie. Cookie payload is opaque to ClickUp; we sign it
/// just enough to detect tampering.
export function mintState(opts: { userId: string; returnTo?: string }): {
  nonce: string
  cookieValue: string
} {
  const nonce = crypto.randomBytes(24).toString("hex")
  const payload: OauthStatePayload = {
    nonce,
    userId: opts.userId,
    returnTo: opts.returnTo,
    iat: Math.floor(Date.now() / 1000),
  }
  const secret = process.env.OAUTH_STATE_SECRET || process.env.CRON_SECRET || "dev-only-secret"
  const body = Buffer.from(JSON.stringify(payload)).toString("base64url")
  const sig = crypto
    .createHmac("sha256", secret)
    .update(body)
    .digest("base64url")
  return { nonce, cookieValue: `${body}.${sig}` }
}

export function verifyState(cookieValue: string | undefined, returnedNonce: string): OauthStatePayload | null {
  if (!cookieValue || !returnedNonce) return null
  const [body, sig] = cookieValue.split(".")
  if (!body || !sig) return null
  const secret = process.env.OAUTH_STATE_SECRET || process.env.CRON_SECRET || "dev-only-secret"
  const expected = crypto.createHmac("sha256", secret).update(body).digest("base64url")
  if (sig !== expected) return null
  let payload: OauthStatePayload
  try {
    payload = JSON.parse(Buffer.from(body, "base64url").toString("utf8"))
  } catch {
    return null
  }
  if (payload.nonce !== returnedNonce) return null
  if (Date.now() / 1000 - payload.iat > OAUTH_STATE_TTL_SEC) return null
  return payload
}

export function buildAuthorizeUrl(opts: {
  clientId: string
  redirectUri: string
  state: string
}): string {
  const u = new URL(CLICKUP_AUTHORIZE_URL)
  u.searchParams.set("client_id", opts.clientId)
  u.searchParams.set("redirect_uri", opts.redirectUri)
  u.searchParams.set("state", opts.state)
  return u.toString()
}

export type TokenExchangeResult = {
  accessToken: string
}

export async function exchangeCodeForToken(opts: {
  clientId: string
  clientSecret: string
  code: string
}): Promise<TokenExchangeResult> {
  // Send as form-encoded body (the OAuth 2.0 standard). ClickUp historically
  // accepted query string too, but body is what their docs document and
  // what other OAuth providers expect — keeping it portable.
  const body = new URLSearchParams({
    client_id: opts.clientId,
    client_secret: opts.clientSecret,
    code: opts.code,
  })
  const res = await fetch(CLICKUP_TOKEN_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Accept: "application/json",
    },
    body: body.toString(),
  })
  if (!res.ok) {
    const detail = await res.text().catch(() => `HTTP ${res.status}`)
    throw new Error(`ClickUp token exchange failed: ${detail.slice(0, 300)}`)
  }
  const json = await res.json() as { access_token?: string; err?: string }
  if (!json.access_token) {
    throw new Error(`ClickUp token exchange returned no access_token: ${json.err ?? JSON.stringify(json).slice(0, 200)}`)
  }
  return { accessToken: json.access_token }
}

/// Build the Authorization header value for a ClickUp API request.
/// ClickUp uses TWO different conventions:
///   - Personal API tokens (`pk_...`):  `Authorization: pk_xxx`     (no prefix)
///   - OAuth access tokens:              `Authorization: Bearer xxx` (Bearer prefix)
/// Both kinds of credentials live in the same `credentials.access_token`
/// (or legacy `credentials.api_key`) field on the connection row, so every
/// API call routes through this helper to pick the right form.
export function clickupAuthHeader(token: string): string {
  if (token.startsWith("pk_")) return token        // personal API token
  return `Bearer ${token}`                          // OAuth access token
}

/// Fetch the authorized user (proves the token works + gives us a name to
/// display on the connection card without needing an extra request later).
export async function fetchAuthorizedUser(accessToken: string): Promise<{ id: string; username: string; email?: string }> {
  const res = await fetch(`${CLICKUP_API_BASE}/user`, {
    headers: { Authorization: clickupAuthHeader(accessToken) },
  })
  if (!res.ok) throw new Error(`ClickUp /user failed: HTTP ${res.status}`)
  const json = await res.json() as { user?: { id: number; username: string; email?: string } }
  if (!json.user) throw new Error("ClickUp /user returned no user")
  return { id: String(json.user.id), username: json.user.username, email: json.user.email }
}

/// Fetch the user's authorized teams (workspaces). We pick the first one as
/// the default; users with multiple workspaces can switch on the settings page.
export async function fetchAuthorizedTeams(accessToken: string): Promise<Array<{ id: string; name: string }>> {
  const res = await fetch(`${CLICKUP_API_BASE}/team`, {
    headers: { Authorization: clickupAuthHeader(accessToken) },
  })
  if (!res.ok) throw new Error(`ClickUp /team failed: HTTP ${res.status}`)
  const json = await res.json() as { teams?: Array<{ id: string; name: string }> }
  return json.teams ?? []
}
