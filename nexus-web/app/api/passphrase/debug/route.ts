import { NextResponse } from "next/server"

// TEMPORARY: lets us see exactly what env vars are present for passphrase debugging
// Delete this file once passphrase is working
export async function GET() {
  return NextResponse.json({
    IRONHORSE: process.env.IRONHORSE ? `set (${process.env.IRONHORSE.length} chars)` : "NOT SET",
    ironhorse: process.env.ironhorse ? `set (${process.env.ironhorse.length} chars)` : "NOT SET",
    MAXWELL_PASSPHRASE: process.env.MAXWELL_PASSPHRASE ? `set (${process.env.MAXWELL_PASSPHRASE.length} chars)` : "NOT SET",
    MAXWELL_PIN: process.env.MAXWELL_PIN ? `set (${process.env.MAXWELL_PIN.length} chars)` : "NOT SET",
  })
}
