// Device fingerprint capture for session rows.
//
// We don't ship a full UA-parser dependency — the strings we care about
// (Lumen native, iOS Safari, macOS Safari, the iOS app's Alamofire UA, etc.)
// are short and stable enough to pattern-match. The label is purely
// human-readable; if it falls through to "Unknown device" the user can
// still revoke by row.

import type { NextRequest } from "next/server"

export type DeviceFingerprint = {
  userAgent: string | null
  ipAddress: string | null
  deviceLabel: string
}

export function fingerprintFromRequest(req: NextRequest): DeviceFingerprint {
  const userAgent = req.headers.get("user-agent")
  const isLumen = req.headers.get("X-Lumen-Client") === "1"
  const ipAddress = clientIp(req)
  const deviceLabel = labelFor(userAgent, isLumen)
  return { userAgent, ipAddress, deviceLabel }
}

function clientIp(req: NextRequest): string | null {
  // Vercel chains forwards into x-forwarded-for; first entry is the client.
  const fwd = req.headers.get("x-forwarded-for")
  if (fwd) {
    const first = fwd.split(",")[0]?.trim()
    if (first) return first
  }
  return req.headers.get("x-real-ip")
}

function labelFor(ua: string | null, isLumen: boolean): string {
  if (isLumen) return "Mac · Lumen"
  if (!ua) return "Unknown device"

  const platform = detectPlatform(ua)
  const browser = detectBrowser(ua)
  if (platform && browser) return `${platform} · ${browser}`
  if (platform) return platform
  if (browser) return browser
  return "Unknown device"
}

function detectPlatform(ua: string): string | null {
  if (/Apple Watch|watchOS/i.test(ua)) return "Apple Watch"
  if (/iPhone/i.test(ua)) return "iPhone"
  if (/iPad/i.test(ua)) return "iPad"
  if (/Macintosh|Mac OS X/i.test(ua)) return "Mac"
  if (/Android/i.test(ua)) return "Android"
  if (/Windows/i.test(ua)) return "Windows"
  if (/Linux/i.test(ua)) return "Linux"
  return null
}

function detectBrowser(ua: string): string | null {
  // The native iOS app's URLSession UA looks like "nexus-ios/1.0 CFNetwork/..."
  if (/nexus-ios|nexus-watch/i.test(ua)) return "Nexus app"
  if (/Edg\//.test(ua)) return "Edge"
  if (/Chrome\//.test(ua) && !/Edg\//.test(ua)) return "Chrome"
  if (/Firefox\//.test(ua)) return "Firefox"
  if (/Safari\//.test(ua) && !/Chrome\//.test(ua)) return "Safari"
  return null
}
