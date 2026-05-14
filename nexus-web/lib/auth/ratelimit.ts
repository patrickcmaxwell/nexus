// Rate limiting for auth endpoints.
//
// Backed by Upstash Redis via @upstash/ratelimit when the env vars
// UPSTASH_REDIS_REST_URL + UPSTASH_REDIS_REST_TOKEN are set. Without them,
// this module degrades to a no-op (with a single warn at boot) so local
// dev doesn't require a Redis instance.
//
// Usage from a route handler:
//
//   const rl = await checkRateLimit(req, { key: "auth:pin", perMinute: 10, windowMinutes: 5 })
//   if (!rl.allowed) {
//     return NextResponse.json(
//       { error: "RATE_LIMITED", retryAfterSeconds: rl.retryAfter },
//       { status: 429, headers: { "Retry-After": String(rl.retryAfter) } }
//     )
//   }
//
// Limits are intentionally generous — they should never trip a legitimate
// user but turn a brute-force script into a multi-day endeavor.

import { NextRequest } from "next/server"

let limiter: {
  pin?: import("@upstash/ratelimit").Ratelimit
  face?: import("@upstash/ratelimit").Ratelimit
  passphrase?: import("@upstash/ratelimit").Ratelimit
  generic?: import("@upstash/ratelimit").Ratelimit
} | null = null

let warned = false

async function getLimiter() {
  if (limiter) return limiter

  const url = process.env.UPSTASH_REDIS_REST_URL
  const token = process.env.UPSTASH_REDIS_REST_TOKEN

  if (!url || !token) {
    if (!warned) {
      console.warn(
        "[ratelimit] UPSTASH_REDIS_REST_URL/_TOKEN not set — rate limiting DISABLED. " +
        "Production deploys should configure these to protect auth endpoints from brute force."
      )
      warned = true
    }
    return null
  }

  // Dynamic import keeps this module load-free for cold paths.
  const { Ratelimit } = await import("@upstash/ratelimit")
  const { Redis } = await import("@upstash/redis")
  const redis = new Redis({ url, token })

  // Tunables — per-endpoint sliding windows. Generous enough that a
  // legitimate user typing a wrong PIN a few times never trips it.
  limiter = {
    // 10 PIN attempts per 5 min per IP. After that, 5-minute cooldown.
    pin: new Ratelimit({ redis, limiter: Ratelimit.slidingWindow(10, "5 m"), analytics: true, prefix: "rl:pin" }),
    // 30 face match attempts per 5 min per IP. Higher because legitimate
    // multi-frame captures are common and face-api inference is the bottleneck.
    face: new Ratelimit({ redis, limiter: Ratelimit.slidingWindow(30, "5 m"), analytics: true, prefix: "rl:face" }),
    // 20 passphrase attempts per 5 min per IP.
    passphrase: new Ratelimit({ redis, limiter: Ratelimit.slidingWindow(20, "5 m"), analytics: true, prefix: "rl:pass" }),
    // Default catch-all for any other endpoint that opts in.
    generic: new Ratelimit({ redis, limiter: Ratelimit.slidingWindow(60, "5 m"), analytics: true, prefix: "rl:gen" }),
  }
  return limiter
}

export type LimiterKey = "pin" | "face" | "passphrase" | "generic"

export interface RateLimitResult {
  allowed: boolean
  /** Seconds the caller should wait before retrying. 0 when allowed. */
  retryAfter: number
  remaining: number
  limit: number
}

/**
 * Identify the caller for rate-limiting purposes. Prefer the first IP in
 * X-Forwarded-For (Vercel sets this), fall back to a stable header chain.
 * When all else fails, fall back to a "unknown" bucket — better to share
 * a bucket than to skip limiting entirely.
 */
function callerKey(req: NextRequest): string {
  const xff = req.headers.get("x-forwarded-for")
  if (xff) return xff.split(",")[0].trim()
  const realIp = req.headers.get("x-real-ip")
  if (realIp) return realIp
  return "unknown"
}

export async function checkRateLimit(
  req: NextRequest,
  opts: { key: LimiterKey }
): Promise<RateLimitResult> {
  const ls = await getLimiter()
  // Disabled (no Upstash configured): allow everything but log nothing more.
  if (!ls) {
    return { allowed: true, retryAfter: 0, remaining: Infinity, limit: Infinity }
  }
  const rl = ls[opts.key] ?? ls.generic!
  const id = callerKey(req)
  const r = await rl.limit(id)
  return {
    allowed: r.success,
    retryAfter: r.success ? 0 : Math.max(1, Math.ceil((r.reset - Date.now()) / 1000)),
    remaining: r.remaining,
    limit: r.limit,
  }
}
