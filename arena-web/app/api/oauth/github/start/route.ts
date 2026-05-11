import { NextResponse } from "next/server"
import { getActiveHuman } from "@/lib/auth/session"
import {
  buildAuthorizeUrl, mintState,
  GITHUB_OAUTH_STATE_COOKIE, GITHUB_OAUTH_STATE_TTL_SEC,
} from "@/lib/oauth/github"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

export async function GET(req: Request) {
  const me = await getActiveHuman()
  if (!me) return NextResponse.redirect(new URL("/", req.url))

  const clientId = process.env.GITHUB_CLIENT_ID
  if (!clientId) {
    return NextResponse.json({
      error: "GITHUB_CLIENT_ID not configured. Register an OAuth App at https://github.com/settings/developers and set GITHUB_CLIENT_ID + GITHUB_CLIENT_SECRET on arena-web's Vercel env.",
    }, { status: 500 })
  }

  const origin = new URL(req.url).origin
  const redirectUri = `${origin}/api/oauth/github/callback`

  const { nonce, cookieValue } = mintState({ userId: me.authId })
  const authorizeUrl = buildAuthorizeUrl({ clientId, redirectUri, state: nonce })

  const response = NextResponse.redirect(authorizeUrl)
  response.cookies.set(GITHUB_OAUTH_STATE_COOKIE, cookieValue, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: GITHUB_OAUTH_STATE_TTL_SEC,
  })
  return response
}
