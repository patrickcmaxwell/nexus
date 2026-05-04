// Thin helper for calling Arena (the executor) from nexus-web.
// Eve's tool calls go through this — keeps URL + auth + caller header in one place.

export const ARENA_BASE_URL = process.env.ARENA_BASE_URL || "http://localhost:3001"
export const ARENA_SECRET   = process.env.ARENA_SECRET   || "dev-arena-secret-change-me"

export type ArenaCaller = "eve" | "lumen" | "ios" | "manual" | "cron"

export async function callArena(
  action: string,
  body: Record<string, unknown>,
  caller: ArenaCaller = "eve",
): Promise<{ ok: boolean; status: number; data: unknown; error?: string }> {
  const path = action.startsWith("/") ? action : `/${action}`
  try {
    const res = await fetch(`${ARENA_BASE_URL}${path}`, {
      method: "POST",
      headers: {
        "Content-Type":   "application/json",
        "Authorization":  `Bearer ${ARENA_SECRET}`,
        "X-Arena-Caller": caller,
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(20_000),
    })
    const data = await res.json().catch(() => ({}))
    return { ok: res.ok, status: res.status, data, error: res.ok ? undefined : (data as any)?.error }
  } catch (e: unknown) {
    return { ok: false, status: 0, data: null, error: e instanceof Error ? e.message : String(e) }
  }
}

export async function pingArena(): Promise<{ online: boolean; warning?: string }> {
  try {
    const res = await fetch(`${ARENA_BASE_URL}/health`, { signal: AbortSignal.timeout(2_000) })
    if (!res.ok) return { online: false }
    const data = await res.json().catch(() => ({})) as { auth?: string }
    return { online: true, warning: data?.auth?.startsWith("WARNING") ? data.auth : undefined }
  } catch {
    return { online: false }
  }
}
