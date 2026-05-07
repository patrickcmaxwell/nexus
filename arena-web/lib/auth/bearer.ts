import { NextRequest, NextResponse } from "next/server"

// Bearer guard for the executor endpoints (/task/*, /payment/*, /sync/*).
// Eve calls these server-to-server with the shared ARENA_SECRET — there's
// no user session in play. Returns null on success, or a 401 NextResponse
// to pipe straight back from the route handler.

export function requireBearer(req: NextRequest): NextResponse | null {
  const expected = process.env.ARENA_SECRET
  if (!expected || expected === "dev-arena-secret-change-me") {
    if (process.env.NODE_ENV === "production") {
      return NextResponse.json(
        { error: "ARENA_SECRET unset or default value used in production" },
        { status: 500 }
      )
    }
  }
  const auth = req.headers.get("Authorization") || ""
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : null
  if (!token || token !== expected) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }
  return null
}
