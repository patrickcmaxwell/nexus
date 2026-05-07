// /api/security/face/match
//
// Native-camera entry point for the desktop app: accepts a JPEG (or PNG)
// captured natively via AVFoundation, computes a 128-dim face descriptor
// server-side via face-api.js + tfjs-node, then matches against the
// enrolled descriptors on each humans row. On match, mints an nx_session
// cookie just like /api/security/face does.
//
// Why this exists: the prior path embedded a WebView in the desktop app
// purely so face-api.js (browser-only) could compute the descriptor. With
// tfjs-node we can do that compute server-side and let the desktop ship a
// fully native camera UI. Web flow still uses /api/security/face directly
// (browser already has face-api loaded for capture).
export const runtime = "nodejs"
// Models are ~2MB each + tfjs warmup; cap at 30s to leave room for the
// occasional cold start where the inference graph compiles.
export const maxDuration = 30

import { NextRequest, NextResponse } from "next/server"
import { createClient } from "@supabase/supabase-js"
import * as tf from "@tensorflow/tfjs-node"
import * as faceapi from "@vladmandic/face-api"
import path from "node:path"

const MATCH_THRESHOLD = 0.6

function getServiceClient() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { persistSession: false, autoRefreshToken: false } }
  )
}

// Module-level model cache. First request pays the ~1s load cost; subsequent
// requests reuse the in-memory weights.
let modelsLoaded = false
let modelLoadPromise: Promise<void> | null = null
async function ensureModelsLoaded(): Promise<void> {
  if (modelsLoaded) return
  if (modelLoadPromise) return modelLoadPromise
  modelLoadPromise = (async () => {
    const modelPath = path.join(process.cwd(), "public", "models")
    await Promise.all([
      faceapi.nets.tinyFaceDetector.loadFromDisk(modelPath),
      faceapi.nets.faceLandmark68TinyNet.loadFromDisk(modelPath),
      faceapi.nets.faceRecognitionNet.loadFromDisk(modelPath),
    ])
    modelsLoaded = true
  })()
  return modelLoadPromise
}

function euclideanDistance(a: number[], b: number[]): number {
  return Math.sqrt(a.reduce((sum, val, i) => sum + Math.pow(val - b[i], 2), 0))
}

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
  return refs
}

function decodeDataUrl(dataUrl: string): Buffer | null {
  const match = /^data:image\/(png|jpeg|jpg|webp);base64,(.+)$/.exec(dataUrl)
  if (!match) return null
  return Buffer.from(match[2], "base64")
}

export async function POST(req: NextRequest) {
  const { imageDataUrl } = await req.json().catch(() => ({}))

  if (typeof imageDataUrl !== "string") {
    return NextResponse.json({ error: "imageDataUrl required" }, { status: 400 })
  }
  const buffer = decodeDataUrl(imageDataUrl)
  if (!buffer) {
    return NextResponse.json({ error: "Unsupported image format" }, { status: 400 })
  }

  await ensureModelsLoaded()

  // Decode image to a 3-channel tensor; face-api accepts this directly.
  // tidy() prevents the intermediate decoded tensor from leaking once we
  // hand the descriptor off.
  let descriptor: Descriptor | null = null
  try {
    const tensor = tf.node.decodeImage(buffer, 3) as tf.Tensor3D
    try {
      const options = new faceapi.TinyFaceDetectorOptions({ inputSize: 320, scoreThreshold: 0.5 })
      const result = await faceapi
        .detectSingleFace(tensor as unknown as faceapi.TNetInput, options)
        .withFaceLandmarks(true)
        .withFaceDescriptor()
      if (result) descriptor = Array.from(result.descriptor) as number[]
    } finally {
      tensor.dispose()
    }
  } catch (err) {
    console.error("[nexus] face-api inference failed:", err)
    return NextResponse.json({ error: "INFERENCE_FAILED" }, { status: 500 })
  }

  if (!descriptor) {
    return NextResponse.json({ error: "NO_FACE_DETECTED" }, { status: 422 })
  }

  // Match against every active human. Mirrors /api/security/face VERIFY
  // logic — pick the lowest distance under MATCH_THRESHOLD.
  const supabase = getServiceClient()
  const { data: humans, error: selectError } = await supabase
    .from("humans")
    .select("id, display_name, role, face_descriptors, face_descriptor, seed_face_descriptor")
    .eq("status", "active")
  if (selectError) {
    console.error("[nexus] Face match query failed:", selectError.message)
    return NextResponse.json({ error: "VERIFY_QUERY_FAILED" }, { status: 500 })
  }
  if (!humans || humans.length === 0) {
    return NextResponse.json({ error: "NO_REFERENCE" }, { status: 404 })
  }

  let bestMatch: { id: string; name: string; role: string; distance: number } | null = null
  for (const human of humans) {
    const refs = collectReferences(human)
    const refsToCheck = refs.length > 0
      ? refs
      : isValidDescriptor(human.seed_face_descriptor) ? [human.seed_face_descriptor] : []
    for (const ref of refsToCheck) {
      const distance = euclideanDistance(descriptor, ref)
      if (distance <= MATCH_THRESHOLD && (!bestMatch || distance < bestMatch.distance)) {
        bestMatch = { id: human.id, name: human.display_name, role: human.role, distance }
      }
    }
  }

  if (!bestMatch) {
    return NextResponse.json({ error: "FACE_MISMATCH" }, { status: 401 })
  }

  // Mint a session for the matched human. Same shape as the other auth
  // endpoints — env-aware cookie so localhost dev works too.
  const now = new Date().toISOString()
  const expiresAt = new Date(Date.now() + 14 * 24 * 60 * 60 * 1000).toISOString()
  const { data: session } = await supabase
    .from("security_sessions")
    .insert({
      user_id: bestMatch.id,
      team_member_id: bestMatch.id,
      created_at: now,
      last_verified_at: now,
      expires_at: expiresAt,
      auth_method: "face",
      invalidated: false,
    })
    .select("id")
    .single()

  const isProd = process.env.NODE_ENV === "production"
  const isLumenClient = req.headers.get("X-Lumen-Client") === "1"
  const body: Record<string, unknown> = {
    success: true,
    distance: bestMatch.distance,
    name: bestMatch.name,
    role: bestMatch.role,
    redirect: "/dashboard",
  }
  // Lumen clients expect sessionId echoed in the body so they can stash the
  // cookie via WKWebView/URLSession instead of relying on browser cookie jar.
  if (isLumenClient && session?.id) body.sessionId = session.id

  const response = NextResponse.json(body)
  if (session?.id) {
    response.cookies.set("nx_session", session.id, {
      httpOnly: true,
      secure: isProd,
      sameSite: isProd ? "none" : "lax",
      path: "/",
      maxAge: 14 * 24 * 60 * 60,
    })
  }
  return response
}
