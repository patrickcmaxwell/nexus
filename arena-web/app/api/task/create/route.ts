import { NextRequest, NextResponse } from "next/server"
import { requireBearer } from "@/lib/auth/bearer"
import { writeAudit } from "@/lib/audit"
import { findProvider, ConnectionRecord } from "@/lib/providers"
import { getServiceClient } from "@/lib/supabase/service"
import { recordConnectionResult } from "@/lib/connection-health"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

// POST /api/task/create
// Body: { user_id, provider?, title, description?, due_date?, priority?, list_id? }
//
// Creates a task in the requested user's first matching connection's
// provider. If `provider` is omitted, defaults to "clickup". If the user
// has no matching connection, falls back to mock so Eve doesn't crash.
export async function POST(req: NextRequest) {
  const guard = requireBearer(req)
  if (guard) return guard

  const body = await req.json().catch(() => ({}))
  const userId = body.user_id as string | undefined
  const providerId = (body.provider as string | undefined) ?? "clickup"
  const title = body.title as string | undefined

  if (!userId || !title) {
    await writeAudit({
      action: "task/create",
      caller: (req.headers.get("X-Arena-Caller") as any) ?? "eve",
      status: "error",
      errorMsg: "Missing user_id or title",
      payload: body,
    })
    return NextResponse.json({ error: "Missing user_id or title" }, { status: 400 })
  }

  const provider = findProvider(providerId)
  if (!provider || !provider.createTask) {
    await writeAudit({
      action: "task/create",
      caller: (req.headers.get("X-Arena-Caller") as any) ?? "eve",
      status: "error",
      errorMsg: `Unknown or unsupported provider: ${providerId}`,
      payload: body,
    })
    return NextResponse.json({ error: `Unknown provider: ${providerId}` }, { status: 400 })
  }

  // Find the user's connection for this provider, if any.
  const connection = await firstConnection(userId, providerId)

  try {
    const result = connection
      ? await provider.createTask({
          connection,
          title,
          description: body.description as string | undefined,
          dueDate: body.due_date as string | undefined,
          priority: body.priority as any,
        })
      : { mocked: true, detail: `No ${provider.name} connection — task not created` }

    // Mark connection healthy + bump last_used_at on real (non-mocked) calls.
    if (connection && !result.mocked) {
      await recordConnectionResult(connection.id, { ok: true })
    }

    await writeAudit({
      action: "task/create",
      caller: (req.headers.get("X-Arena-Caller") as any) ?? "eve",
      payload: { user_id: userId, provider: providerId, title },
      result,
      status: "success",
    })

    return NextResponse.json({ success: true, ...result })
  } catch (err) {
    const detail = err instanceof Error ? err.message : "createTask failed"
    if (connection) {
      await recordConnectionResult(connection.id, { ok: false, error: detail })
    }
    await writeAudit({
      action: "task/create",
      caller: (req.headers.get("X-Arena-Caller") as any) ?? "eve",
      payload: { user_id: userId, provider: providerId, title },
      status: "error",
      errorMsg: detail,
    })
    return NextResponse.json({ error: detail }, { status: 500 })
  }
}

async function firstConnection(userId: string, providerId: string): Promise<ConnectionRecord | null> {
  const supabase = getServiceClient()
  const { data } = await supabase
    .from("arena_connections")
    .select("id, user_id, provider, label, credentials, config, status, last_used_at, last_error")
    .eq("user_id", userId)
    .eq("provider", providerId)
    .eq("status", "active")
    .limit(1)
    .single()
  if (!data) return null
  return {
    id:         data.id,
    userId:     data.user_id,
    provider:   data.provider as any,
    label:      data.label,
    credentials: (data.credentials as any) ?? {},
    config:     (data.config as any) ?? {},
    status:     data.status as any,
    lastUsedAt: data.last_used_at,
    lastError:  data.last_error,
  }
}
