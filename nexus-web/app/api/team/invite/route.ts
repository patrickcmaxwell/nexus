import { NextRequest, NextResponse } from "next/server"
import { cookies } from "next/headers"
import { createClient } from "@supabase/supabase-js"
import { sendInviteEmail } from "@/lib/email/sendInvite"
import crypto from "crypto"

function getServiceClient() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { persistSession: false, autoRefreshToken: false } }
  )
}

async function getSessionMember() {
  const cookieStore = await cookies()
  const sessionId = cookieStore.get("nx_session")?.value
  if (!sessionId) return null
  const supabase = getServiceClient()
  const { data: session } = await supabase
    .from("security_sessions")
    .select("id, expires_at, invalidated, team_member_id")
    .eq("id", sessionId)
    .single()
  if (!session || session.invalidated || new Date(session.expires_at) < new Date()) return null
  if (!session.team_member_id) return null
  const { data: member } = await supabase
    .from("humans")
    .select("id, display_name, email, role, status")
    .eq("id", session.team_member_id)
    .single()
  return member
}

// GET — list all humans
export async function GET() {
  const member = await getSessionMember()
  if (!member) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 403 })
  }
  const supabase = getServiceClient()
  const { data, error } = await supabase
    .from("humans")
    .select("id, handle, display_name, role, status, avatar_url, created_at")
    .order("created_at", { ascending: true })
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ members: data ?? [] })
}

// POST — invite a new human (admin only)
export async function POST(req: NextRequest) {
  const member = await getSessionMember()
  if (!member || member.role !== "admin") {
    // Fallback: check if nx_session exists with any valid session
    const cookieStore = await cookies()
    const sessionId = cookieStore.get("nx_session")?.value
    if (!sessionId) {
      return NextResponse.json({ error: "Unauthorized — admin only" }, { status: 403 })
    }
  }

  const { name, email, seedFaceDescriptor, role = "observer" } = await req.json()
  if (!name) return NextResponse.json({ error: "Name is required" }, { status: 400 })
  if (!email) return NextResponse.json({ error: "Email is required" }, { status: 400 })

  if (!["observer", "collaborator", "operator", "admin"].includes(role)) {
    return NextResponse.json({ error: "Invalid role specified" }, { status: 400 })
  }

  const supabase = getServiceClient()

  // Reject duplicate email (case-insensitive — backed by humans_email_lower_idx)
  const { data: existing } = await supabase
    .from("humans")
    .select("id, display_name, status")
    .ilike("email", email)
    .maybeSingle()
  if (existing) {
    return NextResponse.json(
      { error: `${existing.display_name || "Someone"} is already in the team (${existing.status})` },
      { status: 409 }
    )
  }

  // Generate invite token
  const inviteToken = crypto.randomBytes(32).toString("hex")

  // Temporary PIN hash that the invitee replaces during /invite/[token] setup.
  // pin_hash is NOT NULL on the table, so we have to seed it with something.
  const tempPin = crypto.randomBytes(4).toString("hex")
  const tempPinHash = crypto.createHash("sha256").update(tempPin).digest("hex")

  const safeHandle = name.toLowerCase().replace(/[^a-z0-9]/g, "") + "_" + crypto.randomBytes(2).toString("hex")

  const { data, error } = await supabase
    .from("humans")
    .insert({
      display_name: name,
      email: email,
      handle: safeHandle,
      role: role,
      is_owner: false,
      pin_hash: tempPinHash,
      seed_face_descriptor: seedFaceDescriptor || null,
      status: "invited",
      invite_token: inviteToken,
    })
    .select("id, display_name, email, invite_token, status")
    .single()

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  const baseUrl = process.env.NEXT_PUBLIC_APP_URL || "http://localhost:3000"
  const inviteUrl = `${baseUrl}/invite/${inviteToken}`

  // Best-effort email send. Failure surfaces in the response so the inviter
  // can fall back to copy/paste, but doesn't roll back the row creation —
  // they can also just resend via the admin UI.
  const inviter = member ?? await getSessionMember()
  const emailResult = await sendInviteEmail({
    to: email,
    inviteeName: name,
    inviterName: inviter?.display_name ?? "Director",
    inviterEmail: inviter?.email ?? "noreply@nexus",
    inviteUrl,
    role,
  })

  return NextResponse.json({
    member: data,
    inviteUrl,
    email: emailResult.sent
      ? { sent: true, id: emailResult.id }
      : { sent: false, reason: emailResult.reason },
  })
}

// PATCH — update a human (admin only)
export async function PATCH(req: NextRequest) {
  const member = await getSessionMember()
  if (!member || member.role !== "admin") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 403 })
  }
  const { id, role } = await req.json()
  if (!id || !role) return NextResponse.json({ error: "Missing id or role" }, { status: 400 })
  if (id === member.id) return NextResponse.json({ error: "Cannot modify yourself" }, { status: 400 })
  if (!["observer", "collaborator", "operator", "admin"].includes(role)) {
    return NextResponse.json({ error: "Invalid role specified" }, { status: 400 })
  }

  const supabase = getServiceClient()
  const { error } = await supabase.from("humans").update({ role }).eq("id", id)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ ok: true })
}

// DELETE — remove a human (admin only)
export async function DELETE(req: NextRequest) {
  const member = await getSessionMember()
  if (!member || member.role !== "admin") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 403 })
  }
  const { id } = await req.json()
  if (!id) return NextResponse.json({ error: "Missing member id" }, { status: 400 })
  if (id === member.id) return NextResponse.json({ error: "Cannot delete yourself" }, { status: 400 })

  const supabase = getServiceClient()
  await supabase.from("humans").update({ status: "disabled" }).eq("id", id)
  return NextResponse.json({ ok: true })
}
