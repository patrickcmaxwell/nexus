import { NextResponse } from "next/server"
import { getServiceClient } from "@/lib/supabase/service"
import {
  GITHUB_OAUTH_STATE_COOKIE,
  exchangeCodeForToken, fetchAuthorizedUser, verifyState,
} from "@/lib/oauth/github"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

export async function GET(req: Request) {
  const url = new URL(req.url)
  const code  = url.searchParams.get("code")
  const state = url.searchParams.get("state")
  const error = url.searchParams.get("error")
  const errorDesc = url.searchParams.get("error_description")

  if (error) {
    return NextResponse.redirect(new URL(`/connect/github?error=${encodeURIComponent(errorDesc ?? error)}`, req.url))
  }
  if (!code || !state) {
    return NextResponse.redirect(new URL("/connect/github?error=missing_code", req.url))
  }

  const cookieValue = req.headers.get("cookie")?.split(";")
    .map(s => s.trim())
    .find(s => s.startsWith(`${GITHUB_OAUTH_STATE_COOKIE}=`))
    ?.split("=", 2)[1]
  const payload = verifyState(cookieValue, state)
  if (!payload) {
    return NextResponse.redirect(new URL("/connect/github?error=invalid_state", req.url))
  }

  const clientId = process.env.GITHUB_CLIENT_ID
  const clientSecret = process.env.GITHUB_CLIENT_SECRET
  if (!clientId || !clientSecret) {
    return NextResponse.redirect(new URL("/connect/github?error=server_misconfigured", req.url))
  }

  const origin = new URL(req.url).origin
  const redirectUri = `${origin}/api/oauth/github/callback`

  let token, user
  try {
    token = await exchangeCodeForToken({ clientId, clientSecret, code, redirectUri })
    user  = await fetchAuthorizedUser(token.accessToken)
  } catch (err) {
    console.error("[oauth/github] flow failed:", err)
    const msg = err instanceof Error ? err.message : "token_exchange_failed"
    return NextResponse.redirect(new URL(`/connect/github?error=${encodeURIComponent(msg)}`, req.url))
  }

  const supabase = getServiceClient()
  const { data: existing } = await supabase
    .from("arena_connections")
    .select("id, config")
    .eq("user_id", payload.userId)
    .eq("provider", "github")
    .filter("config->>github_user_id", "eq", String(user.id))
    .maybeSingle()

  const baseConfig = {
    github_user_id: String(user.id),
    github_login:   user.login,
    github_name:    user.name,
    github_avatar:  user.avatar_url,
    scope:          token.scope,
  }

  let connectionId: string
  if (existing) {
    const mergedConfig = { ...(existing.config as Record<string, unknown> ?? {}), ...baseConfig }
    const { error } = await supabase
      .from("arena_connections")
      .update({
        credentials: { access_token: token.accessToken },
        config: mergedConfig,
        status: "active",
        last_error: null,
        updated_at: new Date().toISOString(),
      })
      .eq("id", existing.id)
    if (error) {
      return NextResponse.redirect(new URL(`/connect/github?error=db_update_failed`, req.url))
    }
    connectionId = existing.id
  } else {
    const { data, error } = await supabase
      .from("arena_connections")
      .insert({
        user_id: payload.userId,
        provider: "github",
        label: user.login,
        credentials: { access_token: token.accessToken },
        config: baseConfig,
        status: "active",
      })
      .select("id")
      .single()
    if (error || !data) {
      return NextResponse.redirect(new URL(`/connect/github?error=db_insert_failed`, req.url))
    }
    connectionId = data.id
  }

  const response = NextResponse.redirect(new URL(`/connect/github/${connectionId}/settings?just_connected=1`, req.url))
  response.cookies.delete(GITHUB_OAUTH_STATE_COOKIE)
  return response
}
