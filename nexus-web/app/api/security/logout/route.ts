// POST /api/security/logout — log the active session out.
//
// Hardened 2026-05-08: previously had no auth gate at all, used the wrong
// supabase client (auth-scoped, not service role), and never invalidated
// the row in security_sessions. The cookie was deleted but the session
// record remained valid in the DB — anyone who'd captured the cookie value
// could keep using it. Now: requires a valid session, marks it invalidated,
// then clears the cookie.
import { cookies } from "next/headers"
import { NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { sessionCookieOptions } from "@/lib/auth/cookie"

const COOKIE = "nx_session"

export async function POST() {
  const sessionId = (await cookies()).get(COOKIE)?.value
  if (!sessionId) {
    // Idempotent — already logged out
    return NextResponse.json({ success: true })
  }

  const supabase = createServiceClient()
  await supabase
    .from("security_sessions")
    .update({ invalidated: true })
    .eq("id", sessionId)

  const response = NextResponse.json({ success: true })
  // Set the cookie to empty with maxAge=0 using the same domain/secure config
  // that was used to set it — otherwise the browser keeps the original.
  response.cookies.set(COOKIE, "", { ...sessionCookieOptions({ maxAgeSeconds: 0 }) })
  // Legacy verification cookies — no longer in use but clean up for old clients
  response.cookies.delete("mn_pin_verified")
  response.cookies.delete("mn_face_verified")
  return response
}
