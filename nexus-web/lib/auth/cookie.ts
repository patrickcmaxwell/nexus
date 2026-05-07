// Canonical session-cookie options.
//
// Centralizes the env-aware secure + sameSite combo PLUS the optional
// `domain` attribute that lets the nx_session cookie reach sibling
// subdomains (arena.talkcircles.io, etc).
//
// Setting `domain=.talkcircles.io` widens the cookie scope so any subdomain
// of talkcircles.io can read it. Not set in dev (cookies stay per-host).

const COOKIE_NAME = "nx_session"
const DEFAULT_MAX_AGE = 14 * 24 * 60 * 60   // 14 days

export type CookieOpts = {
  /** Override max age in seconds. Defaults to 14 days. */
  maxAgeSeconds?: number
}

export function sessionCookieOptions(opts: CookieOpts = {}) {
  const isProd = process.env.NODE_ENV === "production"
  const cookieDomain = process.env.SESSION_COOKIE_DOMAIN
  return {
    httpOnly: true,
    secure:   isProd,
    // sameSite=none REQUIRES secure=true. In dev (http) we use lax instead.
    sameSite: (isProd ? "none" : "lax") as "none" | "lax",
    path:     "/",
    maxAge:   opts.maxAgeSeconds ?? DEFAULT_MAX_AGE,
    // domain is only set when explicitly configured via env. Setting it
    // unconditionally would break local dev (browsers reject `.localhost`).
    ...(cookieDomain ? { domain: cookieDomain } : {}),
  }
}

export const SESSION_COOKIE_NAME = COOKIE_NAME
