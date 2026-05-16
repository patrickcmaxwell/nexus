// Derive the canonical public origin for an inbound request.
//
// Why this exists: invite links and recovery URLs need a real domain. We used
// to read `NEXT_PUBLIC_APP_URL` only — when that env var was a placeholder
// (e.g. the literal "https://your-vercel-domain.vercel.app" left over from
// .env.example), invite emails went out with a dead link.
//
// Precedence:
//   1. NEXT_PUBLIC_APP_URL — if set AND looks real (no `your-vercel-domain`,
//      no empty value, parses as a URL).
//   2. The forwarded host on the inbound request (Vercel sets x-forwarded-host
//      / x-forwarded-proto correctly, including for preview deployments).
//   3. Hard-coded production fallback `https://portal.maxnexus.io` for cases
//      where we don't have a request object (cron, schedulers).

import { NextRequest } from "next/server"

const HARD_FALLBACK = "https://portal.maxnexus.io"

function isUsableEnvUrl(raw: string | undefined | null): raw is string {
  if (!raw) return false
  const trimmed = raw.trim()
  if (!trimmed) return false
  if (trimmed.includes("your-vercel-domain")) return false
  try {
    const u = new URL(trimmed)
    if (!u.host) return false
    return true
  } catch {
    return false
  }
}

function stripTrailingSlash(s: string): string {
  return s.endsWith("/") ? s.slice(0, -1) : s
}

/// Public origin (scheme + host, no trailing slash) for the current request.
/// Use this for any URL that's emailed, copied to clipboard, or otherwise
/// surfaces to a human — not for inter-service fetches.
export function publicOrigin(req?: NextRequest): string {
  const env = process.env.NEXT_PUBLIC_APP_URL
  if (isUsableEnvUrl(env)) return stripTrailingSlash(env)

  if (req) {
    const fwdHost = req.headers.get("x-forwarded-host") ?? req.headers.get("host")
    const fwdProto = req.headers.get("x-forwarded-proto") ?? (req.nextUrl.protocol.replace(/:$/, "") || "https")
    if (fwdHost) return stripTrailingSlash(`${fwdProto}://${fwdHost}`)
    if (req.nextUrl?.origin) return stripTrailingSlash(req.nextUrl.origin)
  }

  return HARD_FALLBACK
}
