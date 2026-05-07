// Thin helper for calling Arena (the executor) from nexus-web.
// Eve's tool calls go through this — keeps URL + auth + caller header in one place.
//
// Arena migrated from a standalone Express service to a Next.js app
// (`/code/nexus/arena-web/`). The new app namespaces all routes under
// `/api/*`, so action paths are now `/api/task/create`, `/api/task/update`,
// etc. We accept the old un-prefixed form ("/task/create") and prefix it
// transparently so call sites in /api/eve/route.ts don't have to change.

export const ARENA_BASE_URL = process.env.ARENA_BASE_URL
  || "http://localhost:3001"   // Arena Web dev server runs on :3001 too
export const ARENA_SECRET   = process.env.ARENA_SECRET   || "dev-arena-secret-change-me"

export type ArenaCaller = "eve" | "lumen" | "ios" | "manual" | "cron"

export async function callArena(
  action: string,
  body: Record<string, unknown>,
  caller: ArenaCaller = "eve",
): Promise<{ ok: boolean; status: number; data: unknown; error?: string }> {
  const path = normalizeActionPath(action)
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
    const res = await fetch(`${ARENA_BASE_URL}/api/health`, { signal: AbortSignal.timeout(2_000) })
    if (!res.ok) return { online: false }
    const data = await res.json().catch(() => ({})) as { secretConfigured?: boolean }
    const warning = data?.secretConfigured === false ? "WARNING: Arena ARENA_SECRET unset or default" : undefined
    return { online: true, warning }
  } catch {
    return { online: false }
  }
}

/// Map old un-prefixed action paths to the new /api/-prefixed routes.
/// Keeps call sites stable across the Express → Next.js migration.
function normalizeActionPath(action: string): string {
  const trimmed = action.startsWith("/") ? action : `/${action}`
  if (trimmed.startsWith("/api/")) return trimmed
  return `/api${trimmed}`
}
