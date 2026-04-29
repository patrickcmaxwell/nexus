import { NextRequest, NextResponse } from "next/server"

// This route is no longer needed — auth now goes directly to /dashboard after
// createNexusSession() sets the nx_session cookie. Kept as a fallback redirect.
export async function GET(req: NextRequest) {
  const sessionId = req.cookies.get("nx_session")?.value
  if (!sessionId) {
    return NextResponse.redirect(new URL("/", req.url))
  }
  return NextResponse.redirect(new URL("/dashboard", req.url))
}
