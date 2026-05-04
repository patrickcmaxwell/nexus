import { NextResponse } from "next/server"
import { OLLAMA_BASE_URL, OLLAMA_MODEL } from "@/lib/llm/local"

// Lists models available on the local Ollama daemon. Used by clients
// (web UI / Electron desktop) to populate a brain/model picker. Auth is
// not required — the list is non-sensitive metadata about local infra.
export async function GET() {
  const tagsURL = OLLAMA_BASE_URL.replace(/\/v1\/?$/, "") + "/api/tags"
  try {
    const res = await fetch(tagsURL, { signal: AbortSignal.timeout(3000) })
    if (!res.ok) {
      return NextResponse.json({ online: false, models: [], default: OLLAMA_MODEL }, { status: 200 })
    }
    const json = await res.json() as { models?: Array<{ name: string; size?: number; modified_at?: string }> }
    const models = (json.models ?? []).map(m => ({
      name: m.name,
      size: m.size ?? null,
      modified_at: m.modified_at ?? null,
    }))
    return NextResponse.json({ online: true, models, default: OLLAMA_MODEL })
  } catch {
    return NextResponse.json({ online: false, models: [], default: OLLAMA_MODEL }, { status: 200 })
  }
}
