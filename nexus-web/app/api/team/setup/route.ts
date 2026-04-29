import { NextRequest, NextResponse } from "next/server"
import { createClient } from "@supabase/supabase-js"
import { createNexusSession } from "@/lib/supabase/proxy"
import crypto from "crypto"

function getServiceClient() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { persistSession: false, autoRefreshToken: false } }
  )
}

// GET — validate an invite token
export async function GET(req: NextRequest) {
  const token = req.nextUrl.searchParams.get("token")
  if (!token) return NextResponse.json({ error: "Missing token" }, { status: 400 })

  const supabase = getServiceClient()
  const { data: member } = await supabase
    .from("team_members")
    .select("id, name, status, seed_face_descriptor")
    .eq("invite_token", token)
    .single()

  if (!member) return NextResponse.json({ error: "Invalid invite token" }, { status: 404 })
  if (member.status !== "invited") return NextResponse.json({ error: "Invite already used" }, { status: 410 })

  return NextResponse.json({
    name: member.name,
    hasSeedFace: !!member.seed_face_descriptor,
  })
}

// POST — complete the onboarding (set PIN + face descriptor)
export async function POST(req: NextRequest) {
  const { token, pin, faceDescriptor } = await req.json()

  if (!token || !pin) {
    return NextResponse.json({ error: "Token and PIN are required" }, { status: 400 })
  }

  if (pin.length < 4) {
    return NextResponse.json({ error: "PIN must be at least 4 digits" }, { status: 400 })
  }

  const supabase = getServiceClient()

  // Look up invite
  const { data: member } = await supabase
    .from("team_members")
    .select("id, name, status")
    .eq("invite_token", token)
    .single()

  if (!member) return NextResponse.json({ error: "Invalid invite token" }, { status: 404 })
  if (member.status !== "invited") return NextResponse.json({ error: "Invite already used" }, { status: 410 })

  // Hash the PIN
  const pinHash = crypto.createHash("sha256").update(pin).digest("hex")

  // Activate the member
  const { error: updateErr } = await supabase
    .from("team_members")
    .update({
      pin_hash: pinHash,
      face_descriptor: faceDescriptor || null,
      status: "active",
      invite_token: null, // consume the token
      updated_at: new Date().toISOString(),
    })
    .eq("id", member.id)

  if (updateErr) {
    return NextResponse.json({ error: updateErr.message }, { status: 500 })
  }

  // Create a session for the newly onboarded member
  const response = NextResponse.json({
    success: true,
    name: member.name,
    redirect: "/dashboard",
  })

  return await createNexusSessionForMember(response, member.id)
}

// Helper: create a session tied to a specific team member
async function createNexusSessionForMember(response: NextResponse, memberId: string): Promise<NextResponse> {
  const supabase = getServiceClient()
  const now = new Date().toISOString()
  const expiresAt = new Date(Date.now() + 14 * 24 * 60 * 60 * 1000).toISOString() // 14 days

  const { data, error } = await supabase
    .from("security_sessions")
    .insert({
      user_id: memberId,
      team_member_id: memberId,
      created_at: now,
      last_verified_at: now,
      expires_at: expiresAt,
      auth_method: "invite",
      invalidated: false,
    })
    .select("id")
    .single()

  if (error || !data) {
    console.error("[nexus] Failed to create session:", error?.message)
    return response
  }

  response.cookies.set("nx_session", data.id, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: 14 * 24 * 60 * 60,
  })

  return response
}
