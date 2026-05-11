// /api/oauth/clickup/start
//
// Kicks off the ClickUp OAuth flow. Mints a state token, sets a short-lived
// signed cookie, and redirects the user to ClickUp's consent page.
//
// Requires the user to be signed into Arena/Nexus first (cross-subdomain
// cookie). On success, the user is redirected back to our callback with
// `code` + `state`.

import { NextResponse } from "next/server"
import { getActiveHuman } from "@/lib/auth/session"
import {
  buildAuthorizeUrl, mintState,
  OAUTH_STATE_COOKIE, OAUTH_STATE_TTL_SEC,
} from "@/lib/oauth/clickup"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

export async function GET(req: Request) {
  const me = await getActiveHuman()
  if (!me) {
    // Not signed in — bounce them to portal then back here
    return NextResponse.redirect(new URL("/", req.url))
  }

  const clientId = process.env.CLICKUP_CLIENT_ID
  if (!clientId) {
    return NextResponse.json({
      error: "CLICKUP_CLIENT_ID not configured. Register an OAuth app at https://clickup.com/api/developer-portal/ and set CLICKUP_CLIENT_ID + CLICKUP_CLIENT_SECRET on arena-web's Vercel env.",
    }, { status: 500 })
  }

  // Compute the canonical callback URL. Use the request's own origin so
  // this works on preview deploys too.
  const origin = new URL(req.url).origin
  const redirectUri = `${origin}/api/oauth/clickup/callback`

  const { nonce, cookieValue } = mintState({ userId: me.authId })
  const authorizeUrl = buildAuthorizeUrl({ clientId, redirectUri, state: nonce })

  const response = NextResponse.redirect(authorizeUrl)
  response.cookies.set(OAUTH_STATE_COOKIE, cookieValue, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",  // user navigates back from ClickUp — must survive cross-site redirect
    path: "/",
    maxAge: OAUTH_STATE_TTL_SEC,
  })
  return response
}
