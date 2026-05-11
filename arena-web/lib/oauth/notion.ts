// Notion OAuth helpers.
//
// Differences vs ClickUp OAuth:
//   - Token exchange uses HTTP Basic auth (base64(client_id:client_secret))
//     in the Authorization header, with JSON body — not form-encoded.
//   - Notion has refresh tokens. We store both at first; refresh-token
//     rotation isn't wired in v1, but we have the data.
//   - API calls require a `Notion-Version` header in addition to Bearer.
//   - Authorize URL needs `response_type=code` + `owner=user`.
//
// Reference: https://developers.notion.com/docs/authorization

import crypto from "node:crypto"

export const NOTION_AUTHORIZE_URL = "https://api.notion.com/v1/oauth/authorize"
export const NOTION_TOKEN_URL     = "https://api.notion.com/v1/oauth/token"
export const NOTION_API_BASE      = "https://api.notion.com/v1"
export const NOTION_VERSION       = "2022-06-28"  // pinned; bump deliberately

export const NOTION_OAUTH_STATE_COOKIE = "arena_notion_oauth_state"
export const NOTION_OAUTH_STATE_TTL_SEC = 600

export type NotionStatePayload = {
  nonce: string
  userId: string
  iat: number
}

export function mintState(opts: { userId: string }): { nonce: string; cookieValue: string } {
  const nonce = crypto.randomBytes(24).toString("hex")
  const payload: NotionStatePayload = {
    nonce,
    userId: opts.userId,
    iat: Math.floor(Date.now() / 1000),
  }
  const secret = process.env.OAUTH_STATE_SECRET || process.env.CRON_SECRET || "dev-only-secret"
  const body = Buffer.from(JSON.stringify(payload)).toString("base64url")
  const sig = crypto.createHmac("sha256", secret).update(body).digest("base64url")
  return { nonce, cookieValue: `${body}.${sig}` }
}

export function verifyState(cookieValue: string | undefined, returnedNonce: string): NotionStatePayload | null {
  if (!cookieValue || !returnedNonce) return null
  const [body, sig] = cookieValue.split(".")
  if (!body || !sig) return null
  const secret = process.env.OAUTH_STATE_SECRET || process.env.CRON_SECRET || "dev-only-secret"
  const expected = crypto.createHmac("sha256", secret).update(body).digest("base64url")
  if (sig !== expected) return null
  let payload: NotionStatePayload
  try { payload = JSON.parse(Buffer.from(body, "base64url").toString("utf8")) }
  catch { return null }
  if (payload.nonce !== returnedNonce) return null
  if (Date.now() / 1000 - payload.iat > NOTION_OAUTH_STATE_TTL_SEC) return null
  return payload
}

export function buildAuthorizeUrl(opts: {
  clientId: string
  redirectUri: string
  state: string
}): string {
  const u = new URL(NOTION_AUTHORIZE_URL)
  u.searchParams.set("client_id", opts.clientId)
  u.searchParams.set("redirect_uri", opts.redirectUri)
  u.searchParams.set("response_type", "code")
  u.searchParams.set("owner", "user")
  u.searchParams.set("state", opts.state)
  return u.toString()
}

export type NotionTokenExchangeResult = {
  accessToken: string
  refreshToken: string | null
  workspaceId: string
  workspaceName: string
  workspaceIcon: string | null
  botId: string
  owner: Record<string, unknown> | null
}

export async function exchangeCodeForToken(opts: {
  clientId: string
  clientSecret: string
  code: string
  redirectUri: string
}): Promise<NotionTokenExchangeResult> {
  const basic = Buffer.from(`${opts.clientId}:${opts.clientSecret}`).toString("base64")
  const res = await fetch(NOTION_TOKEN_URL, {
    method: "POST",
    headers: {
      Authorization: `Basic ${basic}`,
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: JSON.stringify({
      grant_type: "authorization_code",
      code: opts.code,
      redirect_uri: opts.redirectUri,
    }),
  })
  if (!res.ok) {
    const detail = await res.text().catch(() => `HTTP ${res.status}`)
    throw new Error(`Notion token exchange failed: ${detail.slice(0, 300)}`)
  }
  const json = await res.json() as {
    access_token?: string
    refresh_token?: string
    workspace_id?: string
    workspace_name?: string
    workspace_icon?: string
    bot_id?: string
    owner?: Record<string, unknown>
  }
  if (!json.access_token || !json.workspace_id || !json.bot_id) {
    throw new Error(`Notion token exchange returned incomplete response: ${JSON.stringify(json).slice(0, 200)}`)
  }
  return {
    accessToken:   json.access_token,
    refreshToken:  json.refresh_token ?? null,
    workspaceId:   json.workspace_id,
    workspaceName: json.workspace_name ?? "Notion workspace",
    workspaceIcon: json.workspace_icon ?? null,
    botId:         json.bot_id,
    owner:         json.owner ?? null,
  }
}

/// Search for databases the integration has access to. Notion's search
/// endpoint with filter.value=database returns databases the bot can see.
export async function searchDatabases(accessToken: string): Promise<Array<{ id: string; title: string; url?: string }>> {
  const res = await fetch(`${NOTION_API_BASE}/search`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Notion-Version": NOTION_VERSION,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      filter: { value: "database", property: "object" },
      page_size: 100,
    }),
  })
  if (!res.ok) {
    const detail = await res.text().catch(() => `HTTP ${res.status}`)
    throw new Error(`Notion search failed: ${detail.slice(0, 200)}`)
  }
  const json = await res.json() as { results?: Array<{ id: string; title?: Array<{ plain_text?: string }>; url?: string }> }
  return (json.results ?? []).map(r => ({
    id: r.id,
    title: (r.title ?? []).map(t => t.plain_text ?? "").join("") || "(untitled)",
    url: r.url,
  }))
}
