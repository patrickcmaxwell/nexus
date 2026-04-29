import { NextResponse } from "next/server"
import { createClient } from "@/lib/supabase/server"

// Logout is always instant — no face scan, no PIN required.
// Security lives on the way IN, not the way OUT.
export async function POST() {
  const supabase = await createClient()

  await supabase.auth.signOut()

  const response = NextResponse.json({ success: true })
  response.cookies.delete("mn_pin_verified")
  response.cookies.delete("mn_face_verified")
  return response
}
