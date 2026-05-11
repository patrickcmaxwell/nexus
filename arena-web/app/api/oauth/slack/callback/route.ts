import { NextResponse } from "next/server"
import { getServiceClient } from "@/lib/supabase/service"
import {
  SLACK_OAUTH_STATE_COOKIE,
  exchangeCodeForToken, verifyState,
} from "@/lib/oauth/slack"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

export async function GET(req: Request) {
  const url = new URL(req.url)
  const code  = url.searchParams.get("code")
  const state = url.searchParams.get("state")
  const error = url.searchParams.get("error")

  if (error) {
    return NextResponse.redirect(new URL(`/connect/slack?error=${encodeURIComponent(error)}`, req.url))
  }
  if (!code || !state) {
    return NextResponse.redirect(new URL("/connect/slack?error=missing_code", req.url))
  }

  const cookieValue = req.headers.get("cookie")?.split(";")
    .map(s => s.trim())
    .find(s => s.startsWith(`${SLACK_OAUTH_STATE_COOKIE}=`))
    ?.split("=", 2)[1]
  const payload = verifyState(cookieValue, state)
  if (!payload) {
    return NextResponse.redirect(new URL("/connect/slack?error=invalid_state", req.url))
  }

  const clientId = process.env.SLACK_CLIENT_ID
  const clientSecret = process.env.SLACK_CLIENT_SECRET
  if (!clientId || !clientSecret) {
    return NextResponse.redirect(new URL("/connect/slack?error=server_misconfigured", req.url))
  }

  const origin = new URL(req.url).origin
  const redirectUri = `${origin}/api/oauth/slack/callback`

  let token
  try {
    token = await exchangeCodeForToken({ clientId, clientSecret, code, redirectUri })
  } catch (err) {
    console.error("[oauth/slack] exchange failed:", err)
    const msg = err instanceof Error ? err.message : "token_exchange_failed"
    return NextResponse.redirect(new URL(`/connect/slack?error=${encodeURIComponent(msg)}`, req.url))
  }

  const supabase = getServiceClient()
  const { data: existing } = await supabase
    .from("arena_connections")
    .select("id, config")
    .eq("user_id", payload.userId)
    .eq("provider", "slack")
    .filter("config->>team_id", "eq", token.teamId)
    .maybeSingle()

  const baseConfig = {
    team_id:        token.teamId,
    team_name:      token.teamName,
    bot_user_id:    token.botUserId,
    app_id:         token.appId,
    authed_user_id: token.authedUserId,
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
      return NextResponse.redirect(new URL(`/connect/slack?error=db_update_failed`, req.url))
    }
    connectionId = existing.id
  } else {
    const { data, error } = await supabase
      .from("arena_connections")
      .insert({
        user_id: payload.userId,
        provider: "slack",
        label: token.teamName,
        credentials: { access_token: token.accessToken },
        config: baseConfig,
        status: "active",
      })
      .select("id")
      .single()
    if (error || !data) {
      return NextResponse.redirect(new URL(`/connect/slack?error=db_insert_failed`, req.url))
    }
    connectionId = data.id
  }

  const response = NextResponse.redirect(new URL(`/connect/slack/${connectionId}/settings?just_connected=1`, req.url))
  response.cookies.delete(SLACK_OAUTH_STATE_COOKIE)
  return response
}
