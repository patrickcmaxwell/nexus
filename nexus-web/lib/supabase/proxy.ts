import { NextResponse, type NextRequest } from "next/server"
import { createClient } from "@supabase/supabase-js"
import { sessionCookieOptions } from "@/lib/auth/cookie"

const COOKIE = "nx_session"
// 14 days — sessions slide on every request so you stay logged in as long as you're active
const SESSION_MINUTES = 60 * 24 * 14

function getClient() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    { auth: { persistSession: false } }
  )
}

export async function updateSession(request: NextRequest) {
  const { pathname } = request.nextUrl

  // Only handle protected paths: dashboard pages and most API routes.
  // Public API routes (login, face auth) handle their own flow.
  const isDashboard = pathname.startsWith("/dashboard")
  const isProtectedApi =
    pathname.startsWith("/api/eve") ||
    pathname.startsWith("/api/operations") ||
    pathname.startsWith("/api/agents") ||
    pathname.startsWith("/api/nexus-map")

  if (!isDashboard && !isProtectedApi) {
    return NextResponse.next({ request })
  }

  const sessionId = request.cookies.get(COOKIE)?.value

  if (!sessionId) {
    // Dashboard pages redirect to login; API routes return 401 JSON.
    if (isDashboard) {
      const url = request.nextUrl.clone()
      url.pathname = "/"
      return NextResponse.redirect(url)
    }
    return NextResponse.next({ request })
  }

  try {
    const supabase = getClient()
    const { data: session } = await supabase
      .from("security_sessions")
      .select("id, expires_at, invalidated")
      .eq("id", sessionId)
      .single()

    const expired = !session || session.invalidated || new Date(session.expires_at) < new Date()

    if (expired) {
      if (isDashboard) {
        const url = request.nextUrl.clone()
        url.pathname = "/"
        const res = NextResponse.redirect(url)
        res.cookies.delete(COOKIE)
        return res
      }
      return NextResponse.next({ request })
    }

    // Slide the expiry window on every authenticated request (page OR api).
    const newExpiry = new Date(Date.now() + SESSION_MINUTES * 60 * 1000).toISOString()
    await supabase
      .from("security_sessions")
      .update({ expires_at: newExpiry, last_verified_at: new Date().toISOString() })
      .eq("id", sessionId)

    // Refresh cookie lifetime so the browser keeps it around. Centralized
    // options pick up SESSION_COOKIE_DOMAIN for subdomain cookie share.
    const res = NextResponse.next({ request })
    res.cookies.set(COOKIE, sessionId, sessionCookieOptions({
      maxAgeSeconds: SESSION_MINUTES * 60,
    }))
    return res
  } catch {
    // DB unavailable — allow through, layer below will re-validate.
    return NextResponse.next({ request })
  }
}

export async function createNexusSession(response: NextResponse, userId?: string, authMethod?: string): Promise<NextResponse> {
  const supabase = createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    { auth: { persistSession: false } }
  )
  const now = new Date().toISOString()
  const expiresAt = new Date(Date.now() + SESSION_MINUTES * 60 * 1000).toISOString()

  // Refuse to create a session without an explicit user_id. The legacy
  // `?? "director"` fallback predated multi-user and would have silently
  // attached fresh sessions to nobody.
  if (!userId) {
    console.error("[nexus] createNexusSession called without userId")
    return response
  }
  const { data, error } = await supabase
    .from("security_sessions")
    .insert({
      user_id: userId,
      created_at: now,
      last_verified_at: now,
      expires_at: expiresAt,
      auth_method: authMethod ?? "face",
      invalidated: false,
    })
    .select("id")
    .single()

  if (error || !data) {
    console.error("[nexus] Failed to create session:", error?.message)
    return response
  }

  response.cookies.set(COOKIE, data.id, sessionCookieOptions({
    maxAgeSeconds: SESSION_MINUTES * 60,
  }))

  return response
}
