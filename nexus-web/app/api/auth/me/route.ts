// GET /api/auth/me — returns the active human's identity bundle.
// Used by the web dashboard + Lumen to render the current-user avatar and
// know what permissions the UI should expose.
import { NextResponse } from "next/server"
import { getActiveHuman } from "@/lib/auth/session"

export async function GET() {
  const human = await getActiveHuman()
  if (!human) {
    return NextResponse.json({ error: "Not authenticated" }, { status: 401 })
  }
  return NextResponse.json({
    humanId: human.humanId,
    email: human.email,
    displayName: human.displayName,
    handle: human.handle,
    role: human.role,
    isOwner: human.isOwner,
    authMethod: human.authMethod,
  })
}
