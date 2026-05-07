import { NextRequest, NextResponse } from "next/server"
import { getActiveAuthId } from "@/lib/auth/session"
import { findProvider } from "@/lib/providers"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

// POST /api/connections/test
// Body: { provider, values }
// Probes the provider's API with the supplied credentials WITHOUT saving
// them. Lets users know if creds are good before committing them.
export async function POST(req: NextRequest) {
  const userId = await getActiveAuthId()
  if (!userId) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })

  const body = await req.json().catch(() => ({}))
  const providerId = body.provider as string | undefined
  const values = (body.values as Record<string, string> | undefined) ?? {}

  if (!providerId) return NextResponse.json({ error: "Missing provider" }, { status: 400 })

  const provider = findProvider(providerId)
  if (!provider) return NextResponse.json({ error: `Unknown provider: ${providerId}` }, { status: 400 })
  if (!provider.testConnection) {
    return NextResponse.json({
      ok: true,
      detail: "This provider doesn't support pre-save testing — credentials will be checked on first use.",
    })
  }

  try {
    const result = await provider.testConnection({ values })
    return NextResponse.json(result)
  } catch (err) {
    return NextResponse.json({
      ok: false,
      detail: err instanceof Error ? err.message : "Test failed",
    }, { status: 500 })
  }
}
