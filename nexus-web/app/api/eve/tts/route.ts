export const maxDuration = 30

import { NextRequest, NextResponse } from "next/server"
import { cookies } from "next/headers"
import { createServiceClient } from "@/lib/supabase/service"

async function checkAuth() {
  const cookieStore = await cookies()
  const sessionId = cookieStore.get("nx_session")?.value
  if (!sessionId) return false
  const supabase = createServiceClient()
  const { data } = await supabase
    .from("security_sessions")
    .select("id, expires_at, invalidated")
    .eq("id", sessionId)
    .single()
  if (!data || data.invalidated) return false
  return new Date(data.expires_at) > new Date()
}

export async function POST(req: NextRequest) {
  if (!await checkAuth()) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }

  const { text } = await req.json()
  if (!text?.trim()) {
    return NextResponse.json({ error: "No text provided" }, { status: 400 })
  }

  const apiKey = process.env.ELEVENLABS_API_KEY
  if (!apiKey) {
    return NextResponse.json({ error: "ELEVENLABS_API_KEY not configured" }, { status: 500 })
  }

  // "EXAVITQu4vr4xnSDxMaL" is Bella, which is allowed on the free tier.
  const VOICE_ID = "EXAVITQu4vr4xnSDxMaL" 

  // ElevenLabs TTS endpoint
  const response = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${VOICE_ID}?output_format=mp3_44100_128`, {
    method: "POST",
    headers: {
      "xi-api-key": apiKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      text: text,
      model_id: "eleven_turbo_v2_5", // Fast model
      voice_settings: {
        stability: 0.5,
        similarity_boost: 0.75
      }
    }),
  })

  if (!response.ok) {
    const err = await response.text()
    console.error("[v0] ElevenLabs TTS error:", err)
    return NextResponse.json({ error: `ElevenLabs TTS error: ${err}` }, { status: response.status })
  }

  // Buffer the full response
  const buffer = await response.arrayBuffer()
  return new Response(buffer, {
    headers: {
      "Content-Type": "audio/mpeg",
      "Content-Length": String(buffer.byteLength),
      "Cache-Control": "no-store",
    },
  })
}
