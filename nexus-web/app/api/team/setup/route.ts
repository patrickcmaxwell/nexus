// Invitee onboarding — completes the invite flow.
//
// GET  ?token=...   — validates the token, returns the invitee's display name.
// POST { token, pin, faceDescriptors?, faceDescriptor?, avatarDataUrl?, directives? }
//   - Sets the invitee's PIN
//   - Stores enrolled face frames (multi-frame array, plus singular for back-compat)
//   - Optional: uploads avatar to storage bucket `avatars/{humanId}.png` and sets avatar_url
//   - Optional: seeds eve_directives rows from the onboarding "tell me about you" answers
//   - Creates the auth.users row so this human owns future data writes
//   - Flips humans.status to active and returns a session cookie
//
// Critical: this is where humans.auth_id gets wired. Without it, the session
// helper can't return a usable user_id for data queries on later logins.
import { NextRequest, NextResponse } from "next/server"
import { createClient } from "@supabase/supabase-js"
import crypto from "crypto"

const COOKIE = "nx_session"
const SESSION_DAYS = 14

function getServiceClient() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { persistSession: false, autoRefreshToken: false } }
  )
}

// Validate an invite token without consuming it
export async function GET(req: NextRequest) {
  const token = req.nextUrl.searchParams.get("token")
  if (!token) return NextResponse.json({ error: "Missing token" }, { status: 400 })

  const supabase = getServiceClient()
  const { data: human } = await supabase
    .from("humans")
    .select("id, display_name, email, status, seed_face_descriptor")
    .eq("invite_token", token)
    .single()

  if (!human) return NextResponse.json({ error: "Invalid invite token" }, { status: 404 })
  if (human.status !== "invited") {
    return NextResponse.json({ error: "Invite already used" }, { status: 410 })
  }

  return NextResponse.json({
    displayName: human.display_name,
    email: human.email,
    hasSeedFace: !!human.seed_face_descriptor,
  })
}

type Descriptor = number[]
type DirectiveSeed = { title: string; content: string }

function isValidDescriptor(d: unknown): d is Descriptor {
  return Array.isArray(d) && d.length === 128 && d.every((v) => typeof v === "number")
}

// Decode a data URL like "data:image/png;base64,iVBOR..." → { mime, buffer }.
// Returns null on malformed input.
function decodeDataUrl(dataUrl: string): { mime: string; buffer: Buffer } | null {
  const match = /^data:(image\/(png|jpeg|webp));base64,(.+)$/.exec(dataUrl)
  if (!match) return null
  return { mime: match[1], buffer: Buffer.from(match[3], "base64") }
}

export async function POST(req: NextRequest) {
  const { token, pin, faceDescriptors, faceDescriptor, avatarDataUrl, directives } = await req.json()

  if (!token || !pin) {
    return NextResponse.json({ error: "Token and PIN are required" }, { status: 400 })
  }
  if (pin.length < 4) {
    return NextResponse.json({ error: "PIN must be at least 4 digits" }, { status: 400 })
  }

  const supabase = getServiceClient()

  const { data: human } = await supabase
    .from("humans")
    .select("id, display_name, email, status")
    .eq("invite_token", token)
    .single()

  if (!human) return NextResponse.json({ error: "Invalid invite token" }, { status: 404 })
  if (human.status !== "invited") {
    return NextResponse.json({ error: "Invite already used" }, { status: 410 })
  }

  // Provision the auth.users row. Random password — auth happens through
  // PIN/face on humans, not against auth.users. The row exists purely as
  // the FK target for user_id columns on data tables.
  const randomPassword = crypto.randomBytes(32).toString("hex")
  const { data: created, error: createErr } = await supabase.auth.admin.createUser({
    email: human.email,
    password: randomPassword,
    email_confirm: true,
  })
  if (createErr || !created?.user) {
    console.error("[nexus] auth.users creation failed:", createErr?.message)
    return NextResponse.json({ error: "Failed to provision identity" }, { status: 500 })
  }
  const authUserId = created.user.id

  // Normalize face frames. Prefer the multi-frame array from the wizard;
  // fall back to single-frame for older clients.
  const validFrames: Descriptor[] = Array.isArray(faceDescriptors)
    ? faceDescriptors.filter(isValidDescriptor)
    : isValidDescriptor(faceDescriptor) ? [faceDescriptor] : []

  // Upload avatar if the wizard captured one. Failure is non-fatal — the
  // human can finish onboarding without an avatar and add one later from
  // /dashboard/settings.
  let avatarUrl: string | null = null
  if (typeof avatarDataUrl === "string" && avatarDataUrl.startsWith("data:image/")) {
    const decoded = decodeDataUrl(avatarDataUrl)
    if (decoded) {
      const ext = decoded.mime === "image/jpeg" ? "jpg" : decoded.mime === "image/webp" ? "webp" : "png"
      const path = `${human.id}.${ext}`
      const { error: uploadErr } = await supabase.storage
        .from("avatars")
        .upload(path, decoded.buffer, { contentType: decoded.mime, upsert: true })
      if (uploadErr) {
        console.error("[nexus] Avatar upload failed:", uploadErr.message)
      } else {
        const { data: pub } = supabase.storage.from("avatars").getPublicUrl(path)
        avatarUrl = pub?.publicUrl ?? null
      }
    }
  }

  const pinHash = crypto.createHash("sha256").update(pin).digest("hex")
  const update: Record<string, unknown> = {
    pin_hash: pinHash,
    auth_id: authUserId,
    status: "active",
    invite_token: null,
  }
  if (validFrames.length > 0) {
    update.face_descriptors = validFrames
    update.face_descriptor = validFrames[0]  // mirror first frame to legacy column
  }
  if (avatarUrl) update.avatar_url = avatarUrl

  const { error: updateErr } = await supabase.from("humans").update(update).eq("id", human.id)
  if (updateErr) {
    return NextResponse.json({ error: updateErr.message }, { status: 500 })
  }

  // Seed eve_directives from the onboarding "about you" answers. These are
  // user-editable later from /dashboard/directives. Skipped silently if the
  // wizard didn't collect any.
  if (Array.isArray(directives) && directives.length > 0) {
    const rows = (directives as DirectiveSeed[])
      .filter((d) => d && typeof d.title === "string" && typeof d.content === "string" && d.content.trim().length > 0)
      .map((d, i) => ({
        user_id: authUserId,
        type: "directive" as const,
        title: d.title.trim().slice(0, 200),
        content: d.content.trim().slice(0, 2000),
        is_active: true,
        priority: 10 - i,
      }))
    if (rows.length > 0) {
      const { error: dirErr } = await supabase.from("eve_directives").insert(rows)
      if (dirErr) console.error("[nexus] Directive seed failed:", dirErr.message)
    }
  }

  // Create session for the freshly-onboarded human.
  const now = new Date().toISOString()
  const expiresAt = new Date(Date.now() + SESSION_DAYS * 24 * 60 * 60 * 1000).toISOString()
  const { data: session } = await supabase
    .from("security_sessions")
    .insert({
      user_id: human.id,
      team_member_id: human.id,
      created_at: now,
      last_verified_at: now,
      expires_at: expiresAt,
      auth_method: "invite",
      invalidated: false,
    })
    .select("id")
    .single()

  const response = NextResponse.json({
    success: true,
    displayName: human.display_name,
    redirect: "/dashboard",
  })
  if (session?.id) {
    response.cookies.set(COOKIE, session.id, {
      httpOnly: true,
      secure: true,
      sameSite: "none",
      path: "/",
      maxAge: SESSION_DAYS * 24 * 60 * 60,
    })
  }
  return response
}
