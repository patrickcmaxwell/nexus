import OpenAI from "openai"

// Ollama exposes an OpenAI-compatible API on /v1. Default to the local daemon
// on the dev machine; override via OLLAMA_BASE_URL when nexus-web runs on a
// different host than the inference box (e.g. Jetson on the LAN).
export const OLLAMA_BASE_URL = process.env.OLLAMA_BASE_URL ?? "http://localhost:11434/v1"
export const OLLAMA_MODEL = process.env.OLLAMA_MODEL ?? "llama3.2:3b"

export function getLocalClient(): OpenAI {
  return new OpenAI({
    baseURL: OLLAMA_BASE_URL,
    apiKey: "ollama", // Ollama ignores the key but the SDK requires a non-empty string
  })
}

export async function pingLocalLLM(): Promise<boolean> {
  try {
    const url = OLLAMA_BASE_URL.replace(/\/v1\/?$/, "") + "/api/tags"
    const res = await fetch(url, { signal: AbortSignal.timeout(2000) })
    return res.ok
  } catch {
    return false
  }
}
