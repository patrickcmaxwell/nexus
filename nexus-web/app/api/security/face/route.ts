import { NextRequest, NextResponse } from "next/server"
import { createClient } from "@supabase/supabase-js"

function getServiceClient() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { persistSession: false, autoRefreshToken: false } }
  )
}

function euclideanDistance(a: number[], b: number[]): number {
  return Math.sqrt(a.reduce((sum, val, i) => sum + Math.pow(val - b[i], 2), 0))
}

const MATCH_THRESHOLD = 0.6

export async function POST(req: NextRequest) {
  const { action, descriptor } = await req.json()
  const supabase = getServiceClient()

  if (!descriptor || !Array.isArray(descriptor) || descriptor.length !== 128) {
    return NextResponse.json({ error: "Invalid descriptor" }, { status: 400 })
  }

  // ENROLL — store face for the calling human
  if (action === "enroll") {
    const sessionId = req.cookies.get("nx_session")?.value
    if (!sessionId) {
      return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
    }

    const { data: session } = await supabase
      .from("security_sessions")
      .select("team_member_id, user_id")
      .eq("id", sessionId)
      .single()

    // team_member_id maps to humans.id (migrated); user_id is the owner fallback
    const humanId = session?.team_member_id ?? session?.user_id
    if (!humanId) {
      return NextResponse.json({ error: "Session has no associated human" }, { status: 401 })
    }

    // If team_member_id isn't in humans (legacy UUID mismatch), fall back to owner
    let targetId = humanId
    const { data: human } = await supabase.from("humans").select("id").eq("id", humanId).single()
    if (!human) {
      const { data: owner } = await supabase.from("humans").select("id").eq("is_owner", true).single()
      if (!owner) return NextResponse.json({ error: "No owner found" }, { status: 500 })
      targetId = owner.id
    }

    const { error: updateError } = await supabase
      .from("humans")
      .update({ face_descriptor: descriptor })
      .eq("id", targetId)

    if (updateError) {
      console.error("[nexus] Face enrollment failed:", updateError.message)
      return NextResponse.json(
        { error: "ENROLL_FAILED", detail: updateError.message },
        { status: 500 }
      )
    }

    return await createHumanSession(
      NextResponse.json({ success: true, action: "enrolled" }),
      targetId, "face", supabase
    )
  }

  // VERIFY — match against all active humans
  if (action === "verify") {
    const { data: humans, error: selectError } = await supabase
      .from("humans")
      .select("id, display_name, role, face_descriptor, seed_face_descriptor")
      .eq("status", "active")

    if (selectError) {
      console.error("[nexus] Face verify query failed:", selectError.message)
      return NextResponse.json(
        { error: "VERIFY_QUERY_FAILED", detail: selectError.message },
        { status: 500 }
      )
    }

    if (!humans || humans.length === 0) {
      return NextResponse.json({ error: "NO_REFERENCE" }, { status: 404 })
    }

    // Only treat enrolled face_descriptor as a reference — seed_face_descriptor alone
    // is a low-quality reference photo that won't reliably match a live scan.
    // If nobody has enrolled yet, return 404 to trigger the enrollment flow.
    const anyEnrolled = humans.some(h => h.face_descriptor)
    if (!anyEnrolled) {
      return NextResponse.json({ error: "NO_REFERENCE" }, { status: 404 })
    }

    let bestMatch: { id: string; name: string; role: string; distance: number } | null = null

    for (const human of humans) {
      // Prefer enrolled face_descriptor; fall back to seed only if no enrolled face exists
      const descriptors = human.face_descriptor
        ? [human.face_descriptor]
        : [human.seed_face_descriptor].filter(Boolean)

      for (const ref of descriptors) {
        const refArr = ref as number[]
        if (!refArr || refArr.length !== 128) continue
        const distance = euclideanDistance(descriptor, refArr)
        if (distance <= MATCH_THRESHOLD && (!bestMatch || distance < bestMatch.distance)) {
          bestMatch = { id: human.id, name: human.display_name, role: human.role, distance }
        }
      }
    }

    if (!bestMatch) {
      return NextResponse.json({ error: "FACE_MISMATCH" }, { status: 401 })
    }

    return await createHumanSession(
      NextResponse.json({ success: true, distance: bestMatch.distance, name: bestMatch.name, redirect: "/dashboard" }),
      bestMatch.id, "face", supabase
    )
  }

  return NextResponse.json({ error: "Unknown action" }, { status: 400 })
}

async function createHumanSession(response: NextResponse, humanId: string, method: string, supabase: any): Promise<NextResponse> {
  const now = new Date().toISOString()
  const expiresAt = new Date(Date.now() + 14 * 24 * 60 * 60 * 1000).toISOString()

  const { data, error } = await supabase
    .from("security_sessions")
    .insert({
      user_id: humanId,
      team_member_id: humanId,
      created_at: now,
      last_verified_at: now,
      expires_at: expiresAt,
      auth_method: method,
      invalidated: false,
    })
    .select("id")
    .single()

  if (error || !data) {
    console.error("[nexus] Failed to create face session:", error?.message)
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
