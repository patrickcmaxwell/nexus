import { NextResponse } from "next/server"
import { getActiveHuman } from "@/lib/auth/session"
import {
  buildAuthorizeUrl, mintState,
  SLACK_OAUTH_STATE_COOKIE, SLACK_OAUTH_STATE_TTL_SEC,
} from "@/lib/oauth/slack"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

export async function GET(req: Request) {
  const me = await getActiveHuman()
  if (!me) return NextResponse.redirect(new URL("/", req.url))

  const clientId = process.env.SLACK_CLIENT_ID
  if (!clientId) {
    return NextResponse.json({
      error: "SLACK_CLIENT_ID not configured. Register an app at https://api.slack.com/apps and set SLACK_CLIENT_ID + SLACK_CLIENT_SECRET on arena-web's Vercel env.",
    }, { status: 500 })
  }

  const origin = new URL(req.url).origin
  const redirectUri = `${origin}/api/oauth/slack/callback`

  const { nonce, cookieValue } = mintState({ userId: me.authId })
  const authorizeUrl = buildAuthorizeUrl({ clientId, redirectUri, state: nonce })

  const response = NextResponse.redirect(authorizeUrl)
  response.cookies.set(SLACK_OAUTH_STATE_COOKIE, cookieValue, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: SLACK_OAUTH_STATE_TTL_SEC,
  })
  return response
}
