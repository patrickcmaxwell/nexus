// Derive the canonical public origin for an inbound request.
//
// Why this exists: invite links and recovery URLs need a real domain. The
// admin is always on the production domain (or a preview deployment they're
// testing) when they issue an invite, so the request origin is the canonical
// answer. The env var is only useful when we don't have a request object —
// e.g. cron jobs, schedule runners, server-side scripts.
//
// Precedence (corrected 2026-05-17 — earlier ordering had a stale env var
// beating the real request origin and produced invite emails pointing to
// `nexus-old.vercel.app`):
//   1. The inbound request's forwarded host (Vercel sets x-forwarded-host
//      / x-forwarded-proto correctly, including for preview deployments).
//   2. NEXT_PUBLIC_APP_URL — when it's set AND looks real (skipped if it's
//      empty, a `your-vercel-domain` placeholder, or a non-https vercel.app
//      preview URL).
//   3. Hard-coded production fallback `https://portal.maxnexus.io` for cases
//      where we don't have a request object AND the env isn't usable.

import { NextRequest } from "next/server"

const PROD_FALLBACK = "https://portal.maxnexus.io"

function isUsableEnvUrl(raw: string | undefined | null): raw is string {
  if (!raw) return false
  const trimmed = raw.trim()
  if (!trimmed) return false
  if (trimmed.includes("your-vercel-domain")) return false
  try {
    const u = new URL(trimmed)
    if (!u.host) return false
    // Reject vercel.app preview URLs as env defaults — they go stale fast,
    // and any production deploy reads its own origin off the request anyway.
    // The env-fallback path is only meant for cron / scheduler / scripts,
    // where pointing users at the canonical production domain is the right
    // behavior, not at last week's preview build.
    if (/\.vercel\.app$/i.test(u.host)) return false
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
  // 1. Request origin wins. Whatever domain the admin's browser hit, the
  //    invitee should land on the same one.
  if (req) {
    const fwdHost = req.headers.get("x-forwarded-host") ?? req.headers.get("host")
    const fwdProto = req.headers.get("x-forwarded-proto") ?? (req.nextUrl.protocol.replace(/:$/, "") || "https")
    if (fwdHost) return stripTrailingSlash(`${fwdProto}://${fwdHost}`)
    if (req.nextUrl?.origin) return stripTrailingSlash(req.nextUrl.origin)
  }

  // 2. Env var, but only when it looks like a real production domain.
  const env = process.env.NEXT_PUBLIC_APP_URL
  if (isUsableEnvUrl(env)) return stripTrailingSlash(env)

  // 3. Last-resort hard-coded prod.
  return PROD_FALLBACK
}
