// /api/oauth/clickup/callback
//
// ClickUp redirects here after the user grants (or denies) access.
//   ?code=...    — exchange this for an access_token
//   ?state=...   — must match the nonce we set in the cookie at /start
//   ?error=...   — user denied or ClickUp errored; we redirect back to /connect
//
// On success: insert/update an arena_connections row, then redirect to
// the per-connection settings page so the user can pick a default list.

import { NextResponse } from "next/server"
import { getServiceClient } from "@/lib/supabase/service"
import {
  OAUTH_STATE_COOKIE,
  exchangeCodeForToken, fetchAuthorizedUser, fetchAuthorizedTeams,
  verifyState,
} from "@/lib/oauth/clickup"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

export async function GET(req: Request) {
  const url = new URL(req.url)
  const code = url.searchParams.get("code")
  const state = url.searchParams.get("state")
  const error = url.searchParams.get("error")

  // User denied or ClickUp errored — bounce them back to /connect/clickup
  // with a friendly query so the page can show what happened.
  if (error) {
    return NextResponse.redirect(new URL(`/connect/clickup?error=${encodeURIComponent(error)}`, req.url))
  }
  if (!code || !state) {
    return NextResponse.redirect(new URL("/connect/clickup?error=missing_code", req.url))
  }

  // CSRF: state in query MUST match the signed nonce in our cookie.
  const cookieValue = req.headers.get("cookie")?.split(";")
    .map(s => s.trim())
    .find(s => s.startsWith(`${OAUTH_STATE_COOKIE}=`))
    ?.split("=", 2)[1]
  const payload = verifyState(cookieValue, state)
  if (!payload) {
    return NextResponse.redirect(new URL("/connect/clickup?error=invalid_state", req.url))
  }

  const clientId = process.env.CLICKUP_CLIENT_ID
  const clientSecret = process.env.CLICKUP_CLIENT_SECRET
  if (!clientId || !clientSecret) {
    return NextResponse.redirect(new URL("/connect/clickup?error=server_misconfigured", req.url))
  }

  // Exchange code → access_token
  let accessToken: string
  try {
    const result = await exchangeCodeForToken({ clientId, clientSecret, code })
    accessToken = result.accessToken
  } catch (err) {
    console.error("[oauth/clickup] token exchange failed:", err)
    const msg = err instanceof Error ? err.message : "token_exchange_failed"
    return NextResponse.redirect(new URL(`/connect/clickup?error=${encodeURIComponent(msg)}`, req.url))
  }

  // Fetch authorized user + teams in parallel — both prove the token works
  // and give us context to show on the settings page.
  let user, teams
  try {
    [user, teams] = await Promise.all([
      fetchAuthorizedUser(accessToken),
      fetchAuthorizedTeams(accessToken),
    ])
  } catch (err) {
    console.error("[oauth/clickup] post-exchange probe failed:", err)
    return NextResponse.redirect(new URL(`/connect/clickup?error=${encodeURIComponent("post_exchange_probe_failed")}`, req.url))
  }

  // Persist connection. If the user already has a clickup connection with
  // the same authorized ClickUp user id, REPLACE its credentials (a
  // re-authorization). Otherwise insert new.
  const supabase = getServiceClient()
  const defaultTeamId = teams[0]?.id ?? null

  const { data: existing } = await supabase
    .from("arena_connections")
    .select("id, config")
    .eq("user_id", payload.userId)
    .eq("provider", "clickup")
    .filter("config->>clickup_user_id", "eq", user.id)
    .maybeSingle()

  let connectionId: string
  if (existing) {
    const mergedConfig = {
      ...(existing.config as Record<string, unknown> ?? {}),
      clickup_user_id: user.id,
      clickup_username: user.username,
      teams,
      default_team_id: (existing.config as Record<string, unknown>)?.default_team_id ?? defaultTeamId,
    }
    const { error } = await supabase
      .from("arena_connections")
      .update({
        credentials: { access_token: accessToken },
        config: mergedConfig,
        status: "active",
        last_error: null,
        updated_at: new Date().toISOString(),
      })
      .eq("id", existing.id)
    if (error) {
      console.error("[oauth/clickup] update failed:", error.message)
      return NextResponse.redirect(new URL(`/connect/clickup?error=${encodeURIComponent("db_update_failed")}`, req.url))
    }
    connectionId = existing.id
  } else {
    const { data, error } = await supabase
      .from("arena_connections")
      .insert({
        user_id: payload.userId,
        provider: "clickup",
        label: user.username,
        credentials: { access_token: accessToken },
        config: {
          clickup_user_id: user.id,
          clickup_username: user.username,
          teams,
          default_team_id: defaultTeamId,
        },
        status: "active",
      })
      .select("id")
      .single()
    if (error || !data) {
      console.error("[oauth/clickup] insert failed:", error?.message)
      return NextResponse.redirect(new URL(`/connect/clickup?error=${encodeURIComponent("db_insert_failed")}`, req.url))
    }
    connectionId = data.id
  }

  // Land on the per-connection settings page. Clear the state cookie.
  const response = NextResponse.redirect(new URL(`/connect/clickup/${connectionId}/settings?just_connected=1`, req.url))
  response.cookies.delete(OAUTH_STATE_COOKIE)
  return response
}
