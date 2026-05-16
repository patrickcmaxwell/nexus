import { NextRequest, NextResponse } from "next/server"
import { createClient } from "@supabase/supabase-js"
import { sessionCookieOptions } from "@/lib/auth/cookie"
import { fingerprintFromRequest } from "@/lib/auth/device"
import { checkRateLimit } from "@/lib/auth/ratelimit"

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

// Auto-learn tunables — mirrors /api/security/face/match. On a confident
// verify, append the probe to face_descriptors[] so the user's reference set
// grows with their natural variations (angles, lighting, glasses, beard, hat).
const AUTO_APPEND_THRESHOLD = 0.4
const DIVERSITY_MIN_DISTANCE = 0.15
const MAX_STORED_DESCRIPTORS = 20

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
  // Include seed as well — best-distance picking still guards the match,
  // so adding more reference vectors can only help (never falsely match).
  // Previously seed was a fallback only when refs was empty, which meant
  // invited users whose face_descriptor was mirrored from a still photo
  // would fail to match a live cam frame on the threshold.
  if (isValidDescriptor(human.seed_face_descriptor)) refs.push(human.seed_face_descriptor)
  return refs
}

export async function POST(req: NextRequest) {
  const rl = await checkRateLimit(req, { key: "face" })
  if (!rl.allowed) {
    return NextResponse.json(
      { error: "RATE_LIMITED", retryAfterSeconds: rl.retryAfter },
      { status: 429, headers: { "Retry-After": String(rl.retryAfter) } }
    )
  }

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

    // Multi-frame replaces the array wholesale (treated as a full re-enroll
    // from the guided 5-angle wizard). Single-frame APPENDS to the existing
    // array — this is the "I uploaded a new photo of myself" flow, and the
    // user expects that new photo to actually be available for matching, not
    // silently dropped because legacy code only wrote to a deprecated column.
    const update: Record<string, unknown> = {}
    if (incomingArray.length > 1) {
      update.face_descriptors = incomingArray
      update.face_descriptor = incomingArray[0]  // mirror first frame to legacy column for back-compat
    } else {
      const { data: existing } = await supabase
        .from("humans")
        .select("face_descriptors")
        .eq("id", targetId)
        .single()
      const current = Array.isArray(existing?.face_descriptors)
        ? (existing!.face_descriptors as unknown[]).filter(isValidDescriptor)
        : []
      const next = [...current, incomingArray[0]]
      if (next.length > MAX_STORED_DESCRIPTORS) {
        // Keep the most recent MAX frames — old ones drift further out of date.
        next.splice(0, next.length - MAX_STORED_DESCRIPTORS)
      }
      update.face_descriptors = next
      update.face_descriptor = incomingArray[0]
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
      targetId, "face", supabase, req
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
    // Track the closest non-matching candidate so we can return it on mismatch
    // for debugging — tells us "Londynn was 0.62 away" vs "totally unknown face."
    let bestNearMiss: { name: string; distance: number } | null = null

    for (const human of humans) {
      const refs = collectReferences(human)
      for (const ref of refs) {
        const distance = euclideanDistance(probe, ref)
        if (distance <= MATCH_THRESHOLD && (!bestMatch || distance < bestMatch.distance)) {
          bestMatch = { id: human.id, name: human.display_name, role: human.role, distance }
        }
        if (!bestNearMiss || distance < bestNearMiss.distance) {
          bestNearMiss = { name: human.display_name, distance }
        }
      }
    }

    if (!bestMatch) {
      return NextResponse.json({
        error: "FACE_MISMATCH",
        nearest: bestNearMiss ? { name: bestNearMiss.name, distance: Number(bestNearMiss.distance.toFixed(3)) } : null,
        threshold: MATCH_THRESHOLD,
      }, { status: 401 })
    }

    // Auto-learn: same logic as /api/security/face/match — on a confident match,
    // fire-and-forget append the probe to face_descriptors[] so the reference
    // set grows with the user's real-world variations.
    if (bestMatch.distance <= AUTO_APPEND_THRESHOLD) {
      const probeDescriptor = probe
      const matched = bestMatch
      ;(async () => {
        try {
          const { data: current } = await supabase
            .from("humans")
            .select("face_descriptors")
            .eq("id", matched.id)
            .single()
          const existing: Descriptor[] = Array.isArray(current?.face_descriptors)
            ? (current!.face_descriptors as unknown[]).filter(isValidDescriptor)
            : []
          if (existing.length >= MAX_STORED_DESCRIPTORS) return
          const minDistToExisting = existing.length === 0
            ? Infinity
            : Math.min(...existing.map((e) => euclideanDistance(probeDescriptor, e)))
          if (minDistToExisting <= DIVERSITY_MIN_DISTANCE) return
          const next = [...existing, probeDescriptor]
          const { error: updateError } = await supabase
            .from("humans")
            .update({ face_descriptors: next })
            .eq("id", matched.id)
          if (updateError) {
            console.error("[face] auto-learn append failed:", updateError.message)
          } else {
            console.log(
              `[face] auto-learned ${matched.name} (web): ${next.length} frames (added at distance ${matched.distance.toFixed(3)}, diversity ${minDistToExisting === Infinity ? "first" : minDistToExisting.toFixed(3)})`
            )
          }
        } catch (err) {
          console.error("[face] auto-learn unexpected error:", err)
        }
      })()
    }

    return await createHumanSession(
      NextResponse.json({
        success: true,
        distance: bestMatch.distance,
        name: bestMatch.name,
        redirect: "/dashboard",
      }),
      bestMatch.id, "face", supabase, req
    )
  }

  return NextResponse.json({ error: "Unknown action" }, { status: 400 })
}

async function createHumanSession(response: NextResponse, humanId: string, method: string, supabase: any, req: NextRequest): Promise<NextResponse> {
  const now = new Date().toISOString()
  const expiresAt = new Date(Date.now() + 14 * 24 * 60 * 60 * 1000).toISOString()
  const fp = fingerprintFromRequest(req)

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
      user_agent: fp.userAgent,
      ip_address: fp.ipAddress,
      device_label: fp.deviceLabel,
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
