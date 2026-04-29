import { NextRequest, NextResponse } from "next/server"
import { createNexusSession } from "@/lib/supabase/proxy"

export async function POST(req: NextRequest) {
  const { passphrase } = await req.json()

  const correct = process.env.MAXWELL_PIN?.trim()

  if (!correct) {
    return NextResponse.json({ error: "PASSPHRASE_NOT_CONFIGURED" }, { status: 500 })
  }

  const input = (passphrase ?? "").trim()

  if (input.toLowerCase() !== correct.toLowerCase()) {
    return NextResponse.json({ error: "INVALID_PASSPHRASE" }, { status: 401 })
  }

  // Create server-side session row — cookie holds DB-backed UUID
  return await createNexusSession(NextResponse.json({ success: true }), "director", "passphrase")
}
