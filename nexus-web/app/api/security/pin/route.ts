import { NextRequest, NextResponse } from "next/server"
import { cookies } from "next/headers"
import { createClient } from "@supabase/supabase-js"
import crypto from "crypto"

const USER_ID = "e9d9a15b-0e5a-4631-9b50-6225ee03a44f"

function getServiceClient() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { persistSession: false, autoRefreshToken: false } }
  )
}

// GET: Check if the PIN cookie is already set (used by login page to skip PIN step)
export async function GET() {
  const cookieStore = await cookies()
  const pinVerified = cookieStore.get("mn_pin_verified")?.value
  if (pinVerified) {
    return NextResponse.json({ verified: true })
  }
  return NextResponse.json({ verified: false }, { status: 401 })
}

export async function POST(req: NextRequest) {
  const { pin, remember } = await req.json()

  if (!pin) {
    return NextResponse.json({ error: "PIN required" }, { status: 400 })
  }

  const supabase = getServiceClient()

  // Hash the submitted PIN
  const pinHash = crypto.createHash("sha256").update(pin).digest("hex")

  // Try to match against team_members first
  const { data: member } = await supabase
    .from("team_members")
    .select("id, name, role")
    .eq("pin_hash", pinHash)
    .eq("status", "active")
    .single()

  if (member) {
    const maxAge = remember ? 60 * 60 * 24 * 30 : 60 * 60 * 8
    const isLumenClient = req.headers.get("X-Lumen-Client") === "1"

    const now = new Date().toISOString()
    const expiresAt = new Date(Date.now() + 14 * 24 * 60 * 60 * 1000).toISOString()
    const { data: session } = await supabase
      .from("security_sessions")
      .insert({
        user_id: member.id,
        team_member_id: member.id,
        created_at: now,
        last_verified_at: now,
        expires_at: expiresAt,
        auth_method: "pin",
        invalidated: false,
      })
      .select("id")
      .single()

    // Guarantee a sessionId for Lumen even if DB insert had a transient failure
    const sessionId = session?.id ?? crypto.randomUUID()

    const body: Record<string, unknown> = { success: true, name: member.name }
    if (isLumenClient) body.sessionId = sessionId

    const response = NextResponse.json(body)
    response.cookies.set("mn_pin_verified", "1", {
      httpOnly: true,
      secure: process.env.NODE_ENV === "production",
      sameSite: "strict",
      path: "/",
      maxAge,
    })
    response.cookies.set("nx_session", sessionId, {
      httpOnly: true,
      secure: process.env.NODE_ENV === "production",
      sameSite: "lax",
      path: "/",
      maxAge: 14 * 24 * 60 * 60,
    })
    response.cookies.set("nx_pending_member", member.id, {
      httpOnly: true,
      secure: process.env.NODE_ENV === "production",
      sameSite: "strict",
      path: "/",
      maxAge: 60 * 10,
    })
    return response
  }

  // Fallback: check MAXWELL_PIN env var (owner access)
  const correctPin = process.env.MAXWELL_PIN
  if (correctPin && pin === correctPin) {
    const maxAge = remember ? 60 * 60 * 24 * 30 : 60 * 60 * 8
    const isLumenClient = req.headers.get("X-Lumen-Client") === "1"

    // Create a session so Lumen desktop gets a usable sessionId
    const now = new Date().toISOString()
    const expiresAt = new Date(Date.now() + 14 * 24 * 60 * 60 * 1000).toISOString()
    const { data: session } = await supabase
      .from("security_sessions")
      .insert({
        user_id: USER_ID,
        created_at: now,
        last_verified_at: now,
        expires_at: expiresAt,
        auth_method: "pin",
        invalidated: false,
      })
      .select("id")
      .single()

    // Guarantee a sessionId for Lumen even if DB insert had a transient failure
    const sessionId = session?.id ?? crypto.randomUUID()

    const body: Record<string, unknown> = { success: true }
    if (isLumenClient) body.sessionId = sessionId

    const response = NextResponse.json(body)
    response.cookies.set("mn_pin_verified", "1", {
      httpOnly: true,
      secure: process.env.NODE_ENV === "production",
      sameSite: "strict",
      path: "/",
      maxAge,
    })
    response.cookies.set("nx_session", sessionId, {
      httpOnly: true,
      secure: process.env.NODE_ENV === "production",
      sameSite: "lax",
      path: "/",
      maxAge: 14 * 24 * 60 * 60,
    })
    return response
  }

  return NextResponse.json({ error: "INVALID_PIN" }, { status: 401 })
}

// Clears security cookies (called on explicit logout)
export async function DELETE() {
  const response = NextResponse.json({ success: true })
  response.cookies.delete("mn_pin_verified")
  response.cookies.delete("mn_face_verified")
  response.cookies.delete("nx_pending_member")
  return response
}
