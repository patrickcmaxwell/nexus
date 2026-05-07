import { NextRequest, NextResponse } from "next/server"
import { createClient } from "@supabase/supabase-js"
import { sessionCookieOptions } from "@/lib/auth/cookie"

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

type Descriptor = number[]

function isValidDescriptor(d: unknown): d is Descriptor {
  return Array.isArray(d) && d.length === 128 && d.every((v) => typeof v === "number")
}

function collectReferences(human: {
  face_descriptors?: unknown
  face_descriptor?: unknown
  seed_face_descriptor?: unknown
}): Descriptor[] {
  const refs: Descriptor[] = []
  if (Array.isArray(human.face_descriptors)) {
    for (const d of human.face_descriptors) if (isValidDescriptor(d)) refs.push(d)
  }
  if (isValidDescriptor(human.face_descriptor)) refs.push(human.face_descriptor)
  // seed is a low-quality reference; only used if nothing better exists
  return refs
}

export async function POST(req: NextRequest) {
  const body = await req.json()
  const { action } = body
  const supabase = getServiceClient()

  // Accept either `descriptor` (single, legacy) or `descriptors` (array, new).
  const incomingArray: Descriptor[] = Array.isArray(body.descriptors)
    ? body.descriptors.filter(isValidDescriptor)
    : isValidDescriptor(body.descriptor)
      ? [body.descriptor]
      : []

  if (incomingArray.length === 0) {
    return NextResponse.json({ error: "Invalid descriptor(s)" }, { status: 400 })
  }

  // ENROLL — store one or more frames for the calling human
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

    const humanId = session?.team_member_id ?? session?.user_id
    if (!humanId) {
      return NextResponse.json({ error: "Session has no associated human" }, { status: 401 })
    }

    let targetId = humanId
    const { data: human } = await supabase.from("humans").select("id").eq("id", humanId).single()
    if (!human) {
      const { data: owner } = await supabase.from("humans").select("id").eq("is_owner", true).single()
      if (!owner) return NextResponse.json({ error: "No owner found" }, { status: 500 })
      targetId = owner.id
    }

    // Multi-frame replaces the array wholesale; single-frame appends.
    const update: Record<string, unknown> = {}
    if (incomingArray.length > 1) {
      update.face_descriptors = incomingArray
      update.face_descriptor = incomingArray[0]  // mirror first frame to legacy column for back-compat
    } else {
      update.face_descriptor = incomingArray[0]
      // also append to the array if it's empty so future verifies use the new path
      const { data: existing } = await supabase
        .from("humans")
        .select("face_descriptors")
        .eq("id", targetId)
        .single()
      const current = Array.isArray(existing?.face_descriptors) ? (existing!.face_descriptors as Descriptor[]) : []
      if (current.length === 0) update.face_descriptors = [incomingArray[0]]
    }

    const { error: updateError } = await supabase.from("humans").update(update).eq("id", targetId)
    if (updateError) {
      console.error("[nexus] Face enrollment failed:", updateError.message)
      return NextResponse.json(
        { error: "ENROLL_FAILED", detail: updateError.message },
        { status: 500 }
      )
    }

    return await createHumanSession(
      NextResponse.json({ success: true, action: "enrolled", framesStored: incomingArray.length }),
      targetId, "face", supabase
    )
  }

  // VERIFY — match the single live frame against every stored reference
  if (action === "verify") {
    const probe = incomingArray[0]
    const { data: humans, error: selectError } = await supabase
      .from("humans")
      .select("id, display_name, role, face_descriptors, face_descriptor, seed_face_descriptor")
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

    // Bail to enrollment flow if literally nobody has any enrolled frames.
    const anyEnrolled = humans.some((h) => collectReferences(h).length > 0)
    if (!anyEnrolled) {
      return NextResponse.json({ error: "NO_REFERENCE" }, { status: 404 })
    }

    let bestMatch: { id: string; name: string; role: string; distance: number } | null = null

    for (const human of humans) {
      const refs = collectReferences(human)
      // seed_face_descriptor is a fallback only if no enrolled frames exist for this human
      const refsToCheck = refs.length > 0
        ? refs
        : isValidDescriptor(human.seed_face_descriptor) ? [human.seed_face_descriptor] : []

      for (const ref of refsToCheck) {
        const distance = euclideanDistance(probe, ref)
        if (distance <= MATCH_THRESHOLD && (!bestMatch || distance < bestMatch.distance)) {
          bestMatch = { id: human.id, name: human.display_name, role: human.role, distance }
        }
      }
    }

    if (!bestMatch) {
      return NextResponse.json({ error: "FACE_MISMATCH" }, { status: 401 })
    }

    return await createHumanSession(
      NextResponse.json({
        success: true,
        distance: bestMatch.distance,
        name: bestMatch.name,
        redirect: "/dashboard",
      }),
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

  // Use shared cookie options so the optional SESSION_COOKIE_DOMAIN env
  // var (for arena subdomain cookie share) flows through the face path too.
  response.cookies.set("nx_session", data.id, sessionCookieOptions())

  return response
}
