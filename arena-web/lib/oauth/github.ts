// GitHub OAuth helpers.
//
// Standard OAuth 2.0 web flow. Uses form-encoded token exchange + Accept
// JSON header to get a JSON response (default is form-encoded). Tokens
// don't expire on standard OAuth Apps (vs. GitHub Apps which use refresh).
//
// Scope: `repo` covers public + private issue read/write. If you only need
// public, use `public_repo` instead — narrower blast radius.
//
// Reference: https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps

import crypto from "node:crypto"

export const GITHUB_AUTHORIZE_URL = "https://github.com/login/oauth/authorize"
export const GITHUB_TOKEN_URL     = "https://github.com/login/oauth/access_token"
export const GITHUB_API_BASE      = "https://api.github.com"
export const GITHUB_SCOPE         = "repo"  // issue read/write on public+private

export const GITHUB_OAUTH_STATE_COOKIE  = "arena_github_oauth_state"
export const GITHUB_OAUTH_STATE_TTL_SEC = 600

export type GithubStatePayload = {
  nonce: string
  userId: string
  iat: number
}

export function mintState(opts: { userId: string }): { nonce: string; cookieValue: string } {
  const nonce = crypto.randomBytes(24).toString("hex")
  const payload: GithubStatePayload = {
    nonce, userId: opts.userId, iat: Math.floor(Date.now() / 1000),
  }
  const secret = process.env.OAUTH_STATE_SECRET || process.env.CRON_SECRET || "dev-only-secret"
  const body = Buffer.from(JSON.stringify(payload)).toString("base64url")
  const sig = crypto.createHmac("sha256", secret).update(body).digest("base64url")
  return { nonce, cookieValue: `${body}.${sig}` }
}

export function verifyState(cookieValue: string | undefined, returnedNonce: string): GithubStatePayload | null {
  if (!cookieValue || !returnedNonce) return null
  const [body, sig] = cookieValue.split(".")
  if (!body || !sig) return null
  const secret = process.env.OAUTH_STATE_SECRET || process.env.CRON_SECRET || "dev-only-secret"
  const expected = crypto.createHmac("sha256", secret).update(body).digest("base64url")
  if (sig !== expected) return null
  let payload: GithubStatePayload
  try { payload = JSON.parse(Buffer.from(body, "base64url").toString("utf8")) }
  catch { return null }
  if (payload.nonce !== returnedNonce) return null
  if (Date.now() / 1000 - payload.iat > GITHUB_OAUTH_STATE_TTL_SEC) return null
  return payload
}

export function buildAuthorizeUrl(opts: {
  clientId: string
  redirectUri: string
  state: string
}): string {
  const u = new URL(GITHUB_AUTHORIZE_URL)
  u.searchParams.set("client_id", opts.clientId)
  u.searchParams.set("redirect_uri", opts.redirectUri)
  u.searchParams.set("scope", GITHUB_SCOPE)
  u.searchParams.set("state", opts.state)
  u.searchParams.set("allow_signup", "false")  // existing GitHub users only
  return u.toString()
}

export type GithubTokenResult = { accessToken: string; scope: string; tokenType: string }

export async function exchangeCodeForToken(opts: {
  clientId: string
  clientSecret: string
  code: string
  redirectUri: string
}): Promise<GithubTokenResult> {
  const body = new URLSearchParams({
    client_id: opts.clientId,
    client_secret: opts.clientSecret,
    code: opts.code,
    redirect_uri: opts.redirectUri,
  })
  const res = await fetch(GITHUB_TOKEN_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Accept: "application/json",
    },
    body: body.toString(),
  })
  if (!res.ok) {
    const detail = await res.text().catch(() => `HTTP ${res.status}`)
    throw new Error(`GitHub token exchange failed: ${detail.slice(0, 300)}`)
  }
  const json = await res.json() as { access_token?: string; scope?: string; token_type?: string; error?: string; error_description?: string }
  if (!json.access_token) {
    throw new Error(`GitHub token exchange returned no access_token: ${json.error_description ?? json.error ?? JSON.stringify(json).slice(0, 200)}`)
  }
  return { accessToken: json.access_token, scope: json.scope ?? "", tokenType: json.token_type ?? "bearer" }
}

export type GithubUser = { id: number; login: string; name: string | null; avatar_url: string }

export async function fetchAuthorizedUser(accessToken: string): Promise<GithubUser> {
  const res = await fetch(`${GITHUB_API_BASE}/user`, {
    headers: { Authorization: `Bearer ${accessToken}`, Accept: "application/vnd.github+json" },
  })
  if (!res.ok) throw new Error(`GitHub /user failed: HTTP ${res.status}`)
  return res.json() as Promise<GithubUser>
}

/// List repos the user has access to. Used in settings page for default-repo picker.
export async function listAuthorizedRepos(accessToken: string): Promise<Array<{ id: number; full_name: string; private: boolean; description: string | null }>> {
  // Pull first page of 100. For users with hundreds of repos, settings page
  // can paginate later; first 100 is enough for most.
  const res = await fetch(`${GITHUB_API_BASE}/user/repos?sort=updated&per_page=100&affiliation=owner,collaborator,organization_member`, {
    headers: { Authorization: `Bearer ${accessToken}`, Accept: "application/vnd.github+json" },
  })
  if (!res.ok) throw new Error(`GitHub /user/repos failed: HTTP ${res.status}`)
  const list = await res.json() as Array<{ id: number; full_name: string; private: boolean; description: string | null }>
  return list
}
