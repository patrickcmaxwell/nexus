import { NextRequest, NextResponse } from "next/server"
import { getActiveAuthId } from "@/lib/auth/session"
import { getServiceClient } from "@/lib/supabase/service"
import { findProvider } from "@/lib/providers"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

// GET /api/connections/[id]
// Returns the connection sans secret values. We never echo `credentials.*`
// back to the client — credential rotations require re-entry.
export async function GET(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const userId = await getActiveAuthId()
  if (!userId) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })

  const { id } = await params
  const supabase = getServiceClient()
  const { data, error } = await supabase
    .from("arena_connections")
    .select("id, provider, label, config, status, last_used_at, last_error, created_at, updated_at, webhook_secret")
    .eq("id", id)
    .eq("user_id", userId)
    .single()
  if (error || !data) return NextResponse.json({ error: "Not found" }, { status: 404 })
  return NextResponse.json({ connection: data })
}

// PATCH /api/connections/[id]
// Body: { label?, values?: Record<string,string> }
//
// Rotates credentials + updates config. For secret fields (per the
// provider's connectFields), only writes when the user supplied a non-empty
// value — leaving the field blank preserves the existing secret. Config
// fields are always updated.
export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const userId = await getActiveAuthId()
  if (!userId) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })

  const { id } = await params
  const body = await req.json().catch(() => ({}))
  const supabase = getServiceClient()

  // Fetch the existing row so we know the provider + can preserve existing
  // credentials when fields are blank.
  const { data: existing } = await supabase
    .from("arena_connections")
    .select("id, provider, credentials, config")
    .eq("id", id)
    .eq("user_id", userId)
    .single()
  if (!existing) return NextResponse.json({ error: "Not found" }, { status: 404 })

  const provider = findProvider(existing.provider as string)
  if (!provider) return NextResponse.json({ error: `Unknown provider on row: ${existing.provider}` }, { status: 500 })

  const update: Record<string, unknown> = {
    updated_at: new Date().toISOString(),
  }

  if (typeof body.label === "string" || body.label === null) {
    update.label = body.label === "" ? null : body.label
  }

  if (body.values && typeof body.values === "object") {
    const incoming = body.values as Record<string, string>
    const existingCreds = (existing.credentials as Record<string, string>) ?? {}
    const existingConfig = (existing.config as Record<string, string>) ?? {}
    const credentials: Record<string, string> = { ...existingCreds }
    const config: Record<string, string> = { ...existingConfig }
    for (const field of provider.connectFields) {
      const v = incoming[field.key]
      if (v === undefined) continue
      if (field.secret) {
        // Preserve existing secret when the user leaves the field blank
        // — a deliberate UX choice so they don't have to retype every
        // secret on a config-only edit.
        if (v !== "") credentials[field.key] = v
      } else {
        config[field.key] = v
      }
    }
    update.credentials = credentials
    update.config = config
  }

  const { error } = await supabase
    .from("arena_connections")
    .update(update)
    .eq("id", id)
    .eq("user_id", userId)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  return NextResponse.json({ success: true })
}
