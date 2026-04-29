import { NextRequest, NextResponse } from "next/server"

export async function GET(req: NextRequest) {
  const cookie = req.cookies.get("mn_passphrase")?.value
  if (cookie === "1") {
    return NextResponse.json({ valid: true })
  }
  return NextResponse.json({ valid: false }, { status: 401 })
}
