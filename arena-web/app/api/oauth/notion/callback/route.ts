// /api/oauth/notion/callback — exchanges the auth code for an access token,
// persists the connection, redirects to the per-connection settings page.
import { NextResponse } from "next/server"
import { getServiceClient } from "@/lib/supabase/service"
import {
  NOTION_OAUTH_STATE_COOKIE,
  exchangeCodeForToken, verifyState,
} from "@/lib/oauth/notion"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

export async function GET(req: Request) {
  const url = new URL(req.url)
  const code = url.searchParams.get("code")
  const state = url.searchParams.get("state")
  const error = url.searchParams.get("error")

  if (error) {
    return NextResponse.redirect(new URL(`/connect/notion?error=${encodeURIComponent(error)}`, req.url))
  }
  if (!code || !state) {
    return NextResponse.redirect(new URL("/connect/notion?error=missing_code", req.url))
  }

  const cookieValue = req.headers.get("cookie")?.split(";")
    .map(s => s.trim())
    .find(s => s.startsWith(`${NOTION_OAUTH_STATE_COOKIE}=`))
    ?.split("=", 2)[1]
  const payload = verifyState(cookieValue, state)
  if (!payload) {
    return NextResponse.redirect(new URL("/connect/notion?error=invalid_state", req.url))
  }

  const clientId = process.env.NOTION_CLIENT_ID
  const clientSecret = process.env.NOTION_CLIENT_SECRET
  if (!clientId || !clientSecret) {
    return NextResponse.redirect(new URL("/connect/notion?error=server_misconfigured", req.url))
  }

  const origin = new URL(req.url).origin
  const redirectUri = `${origin}/api/oauth/notion/callback`

  let token
  try {
    token = await exchangeCodeForToken({ clientId, clientSecret, code, redirectUri })
  } catch (err) {
    console.error("[oauth/notion] exchange failed:", err)
    const msg = err instanceof Error ? err.message : "token_exchange_failed"
    return NextResponse.redirect(new URL(`/connect/notion?error=${encodeURIComponent(msg)}`, req.url))
  }

  const supabase = getServiceClient()
  const { data: existing } = await supabase
    .from("arena_connections")
    .select("id, config")
    .eq("user_id", payload.userId)
    .eq("provider", "notion")
    .filter("config->>workspace_id", "eq", token.workspaceId)
    .maybeSingle()

  let connectionId: string
  const baseConfig = {
    workspace_id: token.workspaceId,
    workspace_name: token.workspaceName,
    workspace_icon: token.workspaceIcon,
    bot_id: token.botId,
    owner: token.owner,
  }
  const credentials: Record<string, string> = { access_token: token.accessToken }
  if (token.refreshToken) credentials.refresh_token = token.refreshToken

  if (existing) {
    const mergedConfig = { ...(existing.config as Record<string, unknown> ?? {}), ...baseConfig }
    const { error } = await supabase
      .from("arena_connections")
      .update({
        credentials,
        config: mergedConfig,
        status: "active",
        last_error: null,
        updated_at: new Date().toISOString(),
      })
      .eq("id", existing.id)
    if (error) {
      return NextResponse.redirect(new URL(`/connect/notion?error=db_update_failed`, req.url))
    }
    connectionId = existing.id
  } else {
    const { data, error } = await supabase
      .from("arena_connections")
      .insert({
        user_id: payload.userId,
        provider: "notion",
        label: token.workspaceName,
        credentials,
        config: baseConfig,
        status: "active",
      })
      .select("id")
      .single()
    if (error || !data) {
      return NextResponse.redirect(new URL(`/connect/notion?error=db_insert_failed`, req.url))
    }
    connectionId = data.id
  }

  const response = NextResponse.redirect(new URL(`/connect/notion/${connectionId}/settings?just_connected=1`, req.url))
  response.cookies.delete(NOTION_OAUTH_STATE_COOKIE)
  return response
}
