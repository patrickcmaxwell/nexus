import { NextRequest, NextResponse } from "next/server"
import { getActiveAuthId } from "@/lib/auth/session"
import { getServiceClient } from "@/lib/supabase/service"
import { findProvider, ALL_PROVIDERS } from "@/lib/providers"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

// GET /api/connections
// Returns all connections for the active human PLUS the catalog of
// available providers (for the "add new connection" UI).
export async function GET() {
  const userId = await getActiveAuthId()
  if (!userId) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })

  const supabase = getServiceClient()
  const { data, error } = await supabase
    .from("arena_connections")
    .select("id, provider, label, status, last_used_at, last_error, created_at")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  return NextResponse.json({
    connections: data ?? [],
    providers: ALL_PROVIDERS.map((p) => ({
      id: p.id, name: p.name, description: p.description, icon: p.icon, accent: p.accent,
    })),
  })
}

// POST /api/connections
// Body: { provider, label?, credentials, config }
// Creates a new connection for the active human. Credentials are stored
// as-is in the JSONB column (Supabase encrypts the column at rest if
// pgcrypto extension is enabled — verify in your project).
export async function POST(req: NextRequest) {
  const userId = await getActiveAuthId()
  if (!userId) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })

  const body = await req.json().catch(() => ({}))
  const providerId = body.provider as string | undefined
  if (!providerId) return NextResponse.json({ error: "Missing provider" }, { status: 400 })

  const provider = findProvider(providerId)
  if (!provider) return NextResponse.json({ error: `Unknown provider: ${providerId}` }, { status: 400 })

  // Validate every required field is present
  const fields = provider.connectFields
  const credentials: Record<string, string> = {}
  const config: Record<string, string> = {}
  for (const field of fields) {
    const value = (body.values as Record<string, string> | undefined)?.[field.key]
    if (field.required && (value === undefined || value === "")) {
      return NextResponse.json({ error: `Missing required field: ${field.label}` }, { status: 400 })
    }
    if (value !== undefined) {
      if (field.secret) credentials[field.key] = value
      else config[field.key] = value
    }
  }

  const supabase = getServiceClient()
  const { data, error } = await supabase
    .from("arena_connections")
    .insert({
      user_id: userId,
      provider: providerId,
      label: (body.label as string | undefined) ?? null,
      credentials,
      config,
      status: "active",
    })
    .select()
    .single()
  if (error) {
    if (error.code === "23505") {
      return NextResponse.json({ error: "A connection with that label already exists" }, { status: 409 })
    }
    return NextResponse.json({ error: error.message }, { status: 500 })
  }

  return NextResponse.json({ connection: data })
}

// DELETE /api/connections?id=<uuid>
export async function DELETE(req: NextRequest) {
  const userId = await getActiveAuthId()
  if (!userId) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })

  const id = new URL(req.url).searchParams.get("id")
  if (!id) return NextResponse.json({ error: "Missing id" }, { status: 400 })

  const supabase = getServiceClient()
  const { error } = await supabase
    .from("arena_connections")
    .delete()
    .eq("id", id)
    .eq("user_id", userId)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  return NextResponse.json({ success: true })
}
