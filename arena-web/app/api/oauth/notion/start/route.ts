// /api/oauth/notion/start — kicks off the Notion OAuth flow.
import { NextResponse } from "next/server"
import { getActiveHuman } from "@/lib/auth/session"
import {
  buildAuthorizeUrl, mintState,
  NOTION_OAUTH_STATE_COOKIE, NOTION_OAUTH_STATE_TTL_SEC,
} from "@/lib/oauth/notion"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

export async function GET(req: Request) {
  const me = await getActiveHuman()
  if (!me) return NextResponse.redirect(new URL("/", req.url))

  const clientId = process.env.NOTION_CLIENT_ID
  if (!clientId) {
    return NextResponse.json({
      error: "NOTION_CLIENT_ID not configured. Register an integration at https://www.notion.so/my-integrations and set NOTION_CLIENT_ID + NOTION_CLIENT_SECRET on arena-web's Vercel env.",
    }, { status: 500 })
  }

  const origin = new URL(req.url).origin
  const redirectUri = `${origin}/api/oauth/notion/callback`

  const { nonce, cookieValue } = mintState({ userId: me.authId })
  const authorizeUrl = buildAuthorizeUrl({ clientId, redirectUri, state: nonce })

  const response = NextResponse.redirect(authorizeUrl)
  response.cookies.set(NOTION_OAUTH_STATE_COOKIE, cookieValue, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: NOTION_OAUTH_STATE_TTL_SEC,
  })
  return response
}
