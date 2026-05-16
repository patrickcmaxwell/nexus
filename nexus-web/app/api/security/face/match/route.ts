// /api/security/face/match
//
// Native-camera entry point for the desktop app: accepts a JPEG (or PNG)
// captured natively via AVFoundation, computes a 128-dim face descriptor
// server-side via face-api.js + @tensorflow/tfjs (CPU backend), then matches
// against the enrolled descriptors on each humans row. On match, mints an
// nx_session cookie just like /api/security/face does.
//
// Why this exists: the prior path embedded a WebView in the desktop app
// purely so face-api.js (browser-only) could compute the descriptor. By
// running the same models server-side we let the desktop ship a fully
// native camera UI. Web flow still uses /api/security/face directly
// (browser already has face-api loaded for capture).
//
// Why pure-JS tfjs (not tfjs-node): tfjs-node ships a 30MB+ libtensorflow
// native binary and pulls in node-pre-gyp's optional AWS-mock deps. The
// resulting Vercel function bundle blew past the 250MB unzipped cap. Pure
// tfjs runs on the CPU backend in pure JS — slower (~500ms/inference vs
// ~150ms), but ships at ~5MB.
export const runtime = "nodejs"
// Models are ~2MB each + tfjs warmup; cap at 30s to leave room for the
// occasional cold start where the inference graph compiles.
export const maxDuration = 30
// Force-dynamic stops Next's build-time page-data collector from importing
// this route — tfjs warmup in the build sandbox can crash with platform
// quirks like "TextEncoder is not a constructor."
export const dynamic = "force-dynamic"

import { NextRequest, NextResponse } from "next/server"
import { createClient } from "@supabase/supabase-js"
import { fingerprintFromRequest } from "@/lib/auth/device"
import path from "node:path"
import { sessionCookieOptions } from "@/lib/auth/cookie"
import { checkRateLimit } from "@/lib/auth/ratelimit"

const MATCH_THRESHOLD = 0.6

// Auto-learn: when a match is *confident* (well under the mismatch threshold)
// AND the new probe descriptor adds diversity to the stored reference set, append
// the probe to face_descriptors[]. Over time the user's reference set grows to
// cover different lighting, angles, glasses-on/off, beard-grown, hat, etc.
// without ever asking them to re-enroll.
//
// Tunables — kept conservative so we never learn off a mediocre match:
//   - AUTO_APPEND_THRESHOLD: only learn from matches clearly inside the gate
//   - DIVERSITY_MIN_DISTANCE: skip a probe too similar to existing refs (no value)
//   - MAX_STORED_DESCRIPTORS: cap the array so it can't grow unbounded
const AUTO_APPEND_THRESHOLD = 0.4
const DIVERSITY_MIN_DISTANCE = 0.15
const MAX_STORED_DESCRIPTORS = 20

function getServiceClient() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { persistSession: false, autoRefreshToken: false } }
  )
}

// Lazy-load tfjs + face-api on first request. Module-level imports execute
// during build-time route inspection where the runtime context is wrong.
let modelsLoaded = false
let modelLoadPromise: Promise<typeof import("@vladmandic/face-api")> | null = null
async function loadFaceApi(): Promise<typeof import("@vladmandic/face-api")> {
  if (modelLoadPromise) return modelLoadPromise
  modelLoadPromise = (async () => {
    // face-api ships several entrypoints. The "main" (face-api.node.js)
    // hard-requires @tensorflow/tfjs-node — a 30MB native binary that
    // blows past Vercel's 250MB function cap. The ESM bundle bakes in the
    // webgl backend which crashes on init in Node ("TextEncoder is not a
    // constructor"). Use the node-wasm entrypoint: pure-JS tfjs + WASM
    // backend, no native binaries, works in any Node environment.
    const faceapi = (await import("@vladmandic/face-api/dist/face-api.node-wasm.js")) as typeof import("@vladmandic/face-api")
    const tfjsWasm = await import("@tensorflow/tfjs-backend-wasm")
    // Use face-api's bundled tf reference so backend registration applies to
    // the SAME tfjs instance face-api will use for inference. Pnpm's strict
    // isolation can hand face-api a different `@tensorflow/tfjs-core` copy
    // than a separate `import("@tensorflow/tfjs")` would touch.
    await tfjsWasm.setWasmPaths(
      `https://cdn.jsdelivr.net/npm/@tensorflow/tfjs-backend-wasm@${tfjsWasm.version_wasm}/dist/`,
    )
    // `faceapi.tf` is re-exported from the bundle but typed as the bare
    // tfjs-core surface here, which doesn't include the public backend
    // helpers. Cast to access them — at runtime they exist on the same
    // tfjs instance that face-api uses for inference.
    const tf = faceapi.tf as unknown as {
      setBackend: (name: string) => Promise<unknown>
      ready: () => Promise<void>
    }
    await tf.setBackend("wasm")
    await tf.ready()
    const modelPath = path.join(process.cwd(), "public", "models")
    await Promise.all([
      faceapi.nets.tinyFaceDetector.loadFromDisk(modelPath),
      faceapi.nets.faceLandmark68TinyNet.loadFromDisk(modelPath),
      faceapi.nets.faceRecognitionNet.loadFromDisk(modelPath),
    ])
    modelsLoaded = true
    return faceapi
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
  if (isValidDescriptor(human.seed_face_descriptor)) refs.push(human.seed_face_descriptor)
  return refs
}

function decodeDataUrl(dataUrl: string): Buffer | null {
  const match = /^data:image\/(png|jpeg|jpg|webp);base64,(.+)$/.exec(dataUrl)
  if (!match) return null
  return Buffer.from(match[2], "base64")
}

export async function POST(req: NextRequest) {
  const rl = await checkRateLimit(req, { key: "face" })
  if (!rl.allowed) {
    return NextResponse.json(
      { error: "RATE_LIMITED", retryAfterSeconds: rl.retryAfter },
      { status: 429, headers: { "Retry-After": String(rl.retryAfter) } }
    )
  }

  const { imageDataUrl } = await req.json().catch(() => ({}))

  if (typeof imageDataUrl !== "string") {
    return NextResponse.json({ error: "imageDataUrl required" }, { status: 400 })
  }
  const buffer = decodeDataUrl(imageDataUrl)
  if (!buffer) {
    return NextResponse.json({ error: "Unsupported image format" }, { status: 400 })
  }

  let faceapi: Awaited<ReturnType<typeof loadFaceApi>>
  // sharp uses CJS `export = sharp;`. Its `.d.ts` doesn't declare a `default`
  // export, but esModuleInterop synthesizes one at runtime. Cast through
  // unknown so the runtime unwrap and the type stay aligned without leaning
  // on `any`.
  let sharp: typeof import("sharp")
  try {
    faceapi = await loadFaceApi()
    const sharpMod = await import("sharp")
    sharp = ((sharpMod as unknown as { default: typeof import("sharp") }).default ?? sharpMod)
  } catch (err) {
    console.error("[nexus] face/match init failed:", err)
    return NextResponse.json({
      error: "INIT_FAILED",
      detail: err instanceof Error ? err.message : String(err),
    }, { status: 500 })
  }

  // Decode JPEG/PNG/WebP to raw RGB pixels via sharp, then wrap as a
  // tf.tensor3d face-api can consume. Use face-api's own tf reference for
  // tensor allocation so allocation + inference happen on the same backend.
  let descriptor: Descriptor | null = null
  try {
    const { data, info } = await sharp(buffer)
      .ensureAlpha()
      .raw()
      .toBuffer({ resolveWithObject: true })
    // sharp returns RGBA bytes; face-api's recognition net wants 3-channel
    // RGB. Strip the alpha and pack into the tensor.
    const pixelCount = info.width * info.height
    const rgb = new Uint8Array(pixelCount * 3)
    for (let i = 0, j = 0; i < data.length; i += 4, j += 3) {
      rgb[j] = data[i]
      rgb[j + 1] = data[i + 1]
      rgb[j + 2] = data[i + 2]
    }
    const tensor = faceapi.tf.tensor3d(rgb, [info.height, info.width, 3], "int32")
    try {
      const options = new faceapi.TinyFaceDetectorOptions({ inputSize: 320, scoreThreshold: 0.5 })
      // detectSingleFace's first arg is TNetInput, exported by face-api. The
      // type lives on the module namespace, not on the runtime value, so
      // reach for it via Parameters<> instead of `faceapi.TNetInput`.
      type FaceInput = Parameters<typeof faceapi.detectSingleFace>[0]
      const result = await faceapi
        .detectSingleFace(tensor as unknown as FaceInput, options)
        .withFaceLandmarks(true)
        .withFaceDescriptor()
      if (result) descriptor = Array.from(result.descriptor) as number[]
    } finally {
      tensor.dispose()
    }
  } catch (err) {
    console.error("[nexus] face-api inference failed:", err)
    return NextResponse.json({
      error: "INFERENCE_FAILED",
      detail: err instanceof Error ? err.message : String(err),
    }, { status: 500 })
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
  let bestNearMiss: { name: string; distance: number } | null = null
  for (const human of humans) {
    const refs = collectReferences(human)
    for (const ref of refs) {
      const distance = euclideanDistance(descriptor, ref)
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

  // Auto-learn: if this match is well inside the gate, fire-and-forget append
  // the live probe to the matched human's face_descriptors[] so future matches
  // have more reference variety (angles, lighting, attire). We do this AFTER
  // bestMatch is decided and BEFORE the session mint so the work happens during
  // the network roundtrip of the session insert below. Errors here never block
  // the auth response — worst case we silently fail to learn this frame.
  if (descriptor && bestMatch.distance <= AUTO_APPEND_THRESHOLD) {
    const probe = descriptor
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
        // Skip if the new probe is too similar to anything already stored —
        // no learning value, just bloat.
        const minDistToExisting = existing.length === 0
          ? Infinity
          : Math.min(...existing.map((e) => euclideanDistance(probe, e)))
        if (minDistToExisting <= DIVERSITY_MIN_DISTANCE) return
        const next = [...existing, probe]
        const { error: updateError } = await supabase
          .from("humans")
          .update({ face_descriptors: next })
          .eq("id", matched.id)
        if (updateError) {
          console.error("[face] auto-learn append failed:", updateError.message)
        } else {
          console.log(
            `[face] auto-learned ${matched.name}: ${next.length} frames (added at distance ${matched.distance.toFixed(3)}, diversity ${minDistToExisting === Infinity ? "first" : minDistToExisting.toFixed(3)})`
          )
        }
      } catch (err) {
        console.error("[face] auto-learn unexpected error:", err)
      }
    })()
  }

  // Mint a session for the matched human. Same shape as the other auth
  // endpoints — env-aware cookie so localhost dev works too.
  const now = new Date().toISOString()
  const expiresAt = new Date(Date.now() + 14 * 24 * 60 * 60 * 1000).toISOString()
  const fp = fingerprintFromRequest(req)
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
      user_agent: fp.userAgent,
      ip_address: fp.ipAddress,
      device_label: fp.deviceLabel,
    })
    .select("id")
    .single()

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
    response.cookies.set("nx_session", session.id, sessionCookieOptions())
  }
  return response
}
