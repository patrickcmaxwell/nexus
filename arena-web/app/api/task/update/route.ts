import { NextRequest, NextResponse } from "next/server"
import { requireBearer } from "@/lib/auth/bearer"
import { writeAudit } from "@/lib/audit"
import { findProvider, ConnectionRecord } from "@/lib/providers"
import { getServiceClient } from "@/lib/supabase/service"
import { recordConnectionResult } from "@/lib/connection-health"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

// POST /api/task/update
// Body: { user_id, provider?, external_id, status?, comment? }
export async function POST(req: NextRequest) {
  const guard = requireBearer(req)
  if (guard) return guard

  const body = await req.json().catch(() => ({}))
  const userId = body.user_id as string | undefined
  const providerId = (body.provider as string | undefined) ?? "clickup"
  const externalId = body.external_id as string | undefined

  if (!userId || !externalId) {
    return NextResponse.json({ error: "Missing user_id or external_id" }, { status: 400 })
  }

  const provider = findProvider(providerId)
  if (!provider || !provider.updateTask) {
    return NextResponse.json({ error: `Unknown provider: ${providerId}` }, { status: 400 })
  }

  const connection = await firstConnection(userId, providerId)

  try {
    const result = connection
      ? await provider.updateTask({
          connection,
          externalId,
          status:  body.status as string | undefined,
          comment: body.comment as string | undefined,
        })
      : { externalId, mocked: true, detail: `No ${provider.name} connection — update skipped` }

    if (connection && !result.mocked) {
      await recordConnectionResult(connection.id, { ok: true })
    }

    await writeAudit({
      action: "task/update",
      caller: (req.headers.get("X-Arena-Caller") as any) ?? "eve",
      payload: { user_id: userId, provider: providerId, external_id: externalId },
      result,
      status: "success",
    })
    return NextResponse.json({ success: true, ...result })
  } catch (err) {
    const detail = err instanceof Error ? err.message : "updateTask failed"
    if (connection) {
      await recordConnectionResult(connection.id, { ok: false, error: detail })
    }
    await writeAudit({
      action: "task/update",
      caller: (req.headers.get("X-Arena-Caller") as any) ?? "eve",
      payload: { user_id: userId, provider: providerId, external_id: externalId },
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
    id: data.id, userId: data.user_id, provider: data.provider as any, label: data.label,
    credentials: (data.credentials as any) ?? {}, config: (data.config as any) ?? {},
    status: data.status as any, lastUsedAt: data.last_used_at, lastError: data.last_error,
  }
}
