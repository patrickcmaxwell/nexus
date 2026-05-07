import { NextRequest, NextResponse } from "next/server"
import { requireBearer } from "@/lib/auth/bearer"
import { writeAudit } from "@/lib/audit"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

// POST /api/sync/push
// Body: { user_id, payload? }
//
// Memory sync push — packages the user's recent Eve memory + outbound
// state and pushes it to a sync target (iPhone, secondary device, etc.).
// Currently shipping as a shape-only stub: validates the call, audit-logs
// it with `mocked: true`, returns success. Real implementation needs a
// product decision on:
//   - what gets bundled (memories? operations? per-window state?)
//   - what the receiver looks like (push to a webhook? S3 bucket? APNs?)
// Eve's `arena_sync_push` tool calls this; safe-mock keeps the audit log
// + the tool response shape consistent.
export async function POST(req: NextRequest) {
  const guard = requireBearer(req)
  if (guard) return guard

  const body = await req.json().catch(() => ({}))
  const userId = body.user_id as string | undefined
  if (!userId) {
    await writeAudit({
      action: "sync/push",
      caller: (req.headers.get("X-Arena-Caller") as any) ?? "eve",
      status: "error",
      errorMsg: "Missing user_id",
      payload: body,
    })
    return NextResponse.json({ error: "Missing user_id" }, { status: 400 })
  }

  const result = {
    pushed: false,
    mocked: true,
    detail: "Sync target not yet wired — push acknowledged but no payload sent",
  }

  await writeAudit({
    action: "sync/push",
    caller: (req.headers.get("X-Arena-Caller") as any) ?? "eve",
    payload: { user_id: userId, payload_keys: Object.keys((body.payload as object) ?? {}) },
    result,
    status: "success",
  })

  return NextResponse.json({ success: true, ...result })
}
