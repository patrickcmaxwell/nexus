// DISABLED 2026-05-08 — security incident.
//
// This endpoint historically accepted a single shared passphrase
// (MAXWELL_PIN env var) and minted an OWNER session for anyone who knew it.
// Combined with the SESSION_COOKIE_DOMAIN=.maxnexus.io cookie scope, that
// effectively let any visitor who guessed (or remembered) one phrase log in
// as Patrick across portal + arena. The splash-page riddle on maxnexus.io
// was layered on top of this and made the surface even larger.
//
// Real auth is /api/security/pin (email + PIN) or /api/security/face. The
// passphrase route is permanently retired — there is no scenario where a
// shared single-secret backdoor that grants owner-level access is acceptable.
//
// All historic sessions created via this endpoint were invalidated in the
// security_sessions table at the same time this file was disabled.
import { NextResponse } from "next/server"

export async function POST() {
  return NextResponse.json(
    {
      error: "ENDPOINT_DISABLED",
      message: "Shared-passphrase login was removed. Use email + PIN at /auth/pin or face scan.",
    },
    { status: 410 }
  )
}
