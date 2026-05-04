export const maxDuration = 30

import { NextRequest, NextResponse } from "next/server"

import { checkDesktopAuth } from "@/lib/desktop-auth"

async function checkAuth(req: NextRequest) {
  return checkDesktopAuth(req)
}

export async function POST(req: NextRequest) {
  if (!await checkAuth(req)) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }

  const { text, voice_id } = await req.json()
  if (!text?.trim()) {
    return NextResponse.json({ error: "No text provided" }, { status: 400 })
  }

  const apiKey = process.env.ELEVENLABS_API_KEY
  if (!apiKey) {
    return NextResponse.json({ error: "ELEVENLABS_API_KEY not configured" }, { status: 500 })
  }

  // Default voice "EXAVITQu4vr4xnSDxMaL" is Bella, allowed on the free tier.
  // Callers can override with any voice_id available on their ElevenLabs
  // account by passing { voice_id: "..." } in the request body.
  const VOICE_ID = (typeof voice_id === "string" && voice_id.length > 0)
    ? voice_id
    : "EXAVITQu4vr4xnSDxMaL"

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
