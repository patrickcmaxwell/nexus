// /api/auth/avatar — manage the active human's avatar image.
//
// POST    — body: { dataUrl: "data:image/...;base64,..." }
//           Decodes, uploads to storage bucket `avatars/{humanId}.{ext}`,
//           writes the public URL onto humans.avatar_url.
// DELETE  — clears humans.avatar_url and removes the storage object.
//
// Storage bucket is public-read; uploads happen via service role here so we
// can validate the input before persisting.
import { NextRequest, NextResponse } from "next/server"
import { createClient } from "@supabase/supabase-js"
import { getActiveHuman } from "@/lib/auth/session"

const MAX_BYTES = 3 * 1024 * 1024  // 3 MB cap on uploaded image

function getServiceClient() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { persistSession: false, autoRefreshToken: false } }
  )
}

function decodeDataUrl(dataUrl: string): { mime: string; ext: string; buffer: Buffer } | null {
  const match = /^data:(image\/(png|jpeg|webp));base64,(.+)$/.exec(dataUrl)
  if (!match) return null
  const ext = match[1] === "image/jpeg" ? "jpg" : match[1] === "image/webp" ? "webp" : "png"
  return { mime: match[1], ext, buffer: Buffer.from(match[3], "base64") }
}

export async function POST(req: NextRequest) {
  const me = await getActiveHuman()
  if (!me) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })

  const { dataUrl } = await req.json().catch(() => ({}))
  if (typeof dataUrl !== "string") {
    return NextResponse.json({ error: "dataUrl required" }, { status: 400 })
  }

  const decoded = decodeDataUrl(dataUrl)
  if (!decoded) return NextResponse.json({ error: "Unsupported image format (png/jpeg/webp only)" }, { status: 400 })
  if (decoded.buffer.length > MAX_BYTES) {
    return NextResponse.json({ error: "Image too large (max 3 MB)" }, { status: 413 })
  }

  const supabase = getServiceClient()
  const path = `${me.humanId}.${decoded.ext}`

  // Clean up any other-extension copies so we don't accumulate stale variants.
  const otherPaths = ["png", "jpg", "webp"].filter((e) => e !== decoded.ext).map((e) => `${me.humanId}.${e}`)
  await supabase.storage.from("avatars").remove(otherPaths).catch(() => {})

  const { error: uploadErr } = await supabase.storage
    .from("avatars")
    .upload(path, decoded.buffer, { contentType: decoded.mime, upsert: true })
  if (uploadErr) {
    return NextResponse.json({ error: uploadErr.message }, { status: 500 })
  }

  const { data: pub } = supabase.storage.from("avatars").getPublicUrl(path)
  // Cache-bust by appending a timestamp param so the new image shows immediately
  const url = `${pub.publicUrl}?v=${Date.now()}`

  const { error: updateErr } = await supabase
    .from("humans")
    .update({ avatar_url: url })
    .eq("id", me.humanId)
  if (updateErr) {
    return NextResponse.json({ error: updateErr.message }, { status: 500 })
  }

  return NextResponse.json({ success: true, avatarUrl: url })
}

export async function DELETE() {
  const me = await getActiveHuman()
  if (!me) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })

  const supabase = getServiceClient()
  const paths = ["png", "jpg", "webp"].map((e) => `${me.humanId}.${e}`)
  await supabase.storage.from("avatars").remove(paths).catch(() => {})
  await supabase.from("humans").update({ avatar_url: null }).eq("id", me.humanId)
  return NextResponse.json({ success: true })
}
