import { NextRequest, NextResponse } from "next/server"
import { createClient } from "@supabase/supabase-js"
import crypto from "crypto"

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

  // ENROLL — update the calling member's face descriptor
  if (action === "enroll") {
    // For enrollment, we need to know who's calling. Check session.
    const sessionId = req.cookies.get("nx_session")?.value
    if (!sessionId) {
      return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
    }
    const { data: session } = await supabase
      .from("security_sessions")
      .select("team_member_id")
      .eq("id", sessionId)
      .single()

    const memberId = session?.team_member_id
    if (!memberId) {
      // Legacy fallback: enroll for the director
      const { data: director } = await supabase
        .from("team_members")
        .select("id")
        .eq("role", "director")
        .single()
      if (!director) return NextResponse.json({ error: "No director found" }, { status: 500 })

      await supabase.from("team_members").update({ face_descriptor: descriptor }).eq("id", director.id)
      return await createMemberSession(
        NextResponse.json({ success: true, action: "enrolled" }),
        director.id, "face", supabase
      )
    }

    await supabase.from("team_members").update({ face_descriptor: descriptor }).eq("id", memberId)
    return await createMemberSession(
      NextResponse.json({ success: true, action: "enrolled" }),
      memberId, "face", supabase
    )
  }

  // VERIFY — match face against ALL active team members
  if (action === "verify") {
    const { data: members } = await supabase
      .from("team_members")
      .select("id, name, role, face_descriptor, seed_face_descriptor")
      .eq("status", "active")

    if (!members || members.length === 0) {
      return NextResponse.json({ error: "NO_REFERENCE" }, { status: 404 })
    }

    let bestMatch: { id: string; name: string; role: string; distance: number } | null = null

    for (const member of members) {
      // Check enrolled face first, then seed face
      const descriptors = [
        member.face_descriptor,
        member.seed_face_descriptor,
      ].filter(Boolean)

      for (const ref of descriptors) {
        const refArr = ref as number[]
        if (!refArr || refArr.length !== 128) continue
        const distance = euclideanDistance(descriptor, refArr)
        if (distance <= MATCH_THRESHOLD && (!bestMatch || distance < bestMatch.distance)) {
          bestMatch = { id: member.id, name: member.name, role: member.role, distance }
        }
      }
    }

    if (!bestMatch) {
      // If no team member match, check legacy face_reference table
      const { data: legacyRef } = await supabase
        .from("face_reference")
        .select("descriptor, user_id")
        .single()

      if (legacyRef) {
        const distance = euclideanDistance(descriptor, legacyRef.descriptor as number[])
        if (distance <= MATCH_THRESHOLD) {
          // Matched legacy — find or create director member
          const { data: director } = await supabase
            .from("team_members")
            .select("id")
            .eq("role", "director")
            .single()

          if (director) {
            return await createMemberSession(
              NextResponse.json({ success: true, distance, name: "Director", redirect: "/dashboard" }),
              director.id, "face", supabase
            )
          }
        }
      }

      return NextResponse.json({ error: "FACE_MISMATCH" }, { status: 401 })
    }

    return await createMemberSession(
      NextResponse.json({ success: true, distance: bestMatch.distance, name: bestMatch.name, redirect: "/dashboard" }),
      bestMatch.id, "face", supabase
    )
  }

  return NextResponse.json({ error: "Unknown action" }, { status: 400 })
}

async function createMemberSession(response: NextResponse, memberId: string, method: string, supabase: any): Promise<NextResponse> {
  const now = new Date().toISOString()
  const expiresAt = new Date(Date.now() + 14 * 24 * 60 * 60 * 1000).toISOString()

  const { data, error } = await supabase
    .from("security_sessions")
    .insert({
      user_id: memberId,
      team_member_id: memberId,
      created_at: now,
      last_verified_at: now,
      expires_at: expiresAt,
      auth_method: method,
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
