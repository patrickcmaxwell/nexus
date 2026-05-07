import { NextRequest, NextResponse } from "next/server"
import { requireBearer } from "@/lib/auth/bearer"
import { writeAudit } from "@/lib/audit"
import { findProvider, ConnectionRecord } from "@/lib/providers"
import { getServiceClient } from "@/lib/supabase/service"
import { recordConnectionResult } from "@/lib/connection-health"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

// POST /api/payment/route
// Body: {
//   user_id, provider?, total_amount, currency, splits: [{ to, amount, note? }]
// }
//
// Validates that splits sum to total (refuse mismatched math), then routes
// to the user's payment provider. Stripe is the only one shipped today;
// it returns a `mocked: true` result until Connect wiring lands.
export async function POST(req: NextRequest) {
  const guard = requireBearer(req)
  if (guard) return guard

  const body = await req.json().catch(() => ({}))
  const userId = body.user_id as string | undefined
  const providerId = (body.provider as string | undefined) ?? "stripe"
  const totalAmount = Number(body.total_amount)
  const currency = (body.currency as string | undefined) ?? "usd"
  const splits = (body.splits as Array<{ to: string; amount: number; note?: string }> | undefined) ?? []

  if (!userId) {
    return jsonError("Missing user_id", 400)
  }
  if (!isFinite(totalAmount) || totalAmount <= 0) {
    return jsonError("total_amount must be a positive number", 400)
  }
  if (!Array.isArray(splits) || splits.length === 0) {
    return jsonError("splits must be a non-empty array", 400)
  }

  // Math check — refuse before anything irreversible. Round to cents for
  // floating-point hygiene; Stripe expects integer minor units anyway.
  const splitSum = splits.reduce((s, x) => s + Number(x.amount || 0), 0)
  const drift = Math.abs(splitSum - totalAmount)
  if (drift > 0.005) {
    await writeAudit({
      action: "payment/route",
      caller: (req.headers.get("X-Arena-Caller") as any) ?? "eve",
      payload: { user_id: userId, total_amount: totalAmount, splits },
      status: "error",
      errorMsg: `Split sum ${splitSum.toFixed(2)} doesn't match total ${totalAmount.toFixed(2)}`,
    })
    return jsonError(`Splits must sum to total. Got ${splitSum.toFixed(2)} vs ${totalAmount.toFixed(2)}.`, 400)
  }

  const provider = findProvider(providerId)
  if (!provider || !provider.routePayment) {
    return jsonError(`Provider ${providerId} doesn't support payment routing`, 400)
  }

  const connection = await firstConnection(userId, providerId)

  try {
    const result = connection
      ? await provider.routePayment({
          connection,
          totalAmount,
          currency,
          splits,
        })
      : { routedAmount: totalAmount, recipients: splits.length, mocked: true,
          detail: `No ${provider.name} connection — payment mocked` }

    if (connection && !result.mocked) {
      await recordConnectionResult(connection.id, { ok: true })
    }

    await writeAudit({
      action: "payment/route",
      caller: (req.headers.get("X-Arena-Caller") as any) ?? "eve",
      payload: { user_id: userId, total_amount: totalAmount, currency, splits },
      result,
      status: "success",
    })
    return NextResponse.json({ success: true, ...result })
  } catch (err) {
    const detail = err instanceof Error ? err.message : "routePayment failed"
    if (connection) {
      await recordConnectionResult(connection.id, { ok: false, error: detail })
    }
    await writeAudit({
      action: "payment/route",
      caller: (req.headers.get("X-Arena-Caller") as any) ?? "eve",
      payload: { user_id: userId, total_amount: totalAmount, currency, splits },
      status: "error",
      errorMsg: detail,
    })
    return jsonError(detail, 500)
  }
}

function jsonError(error: string, status: number): NextResponse {
  return NextResponse.json({ error }, { status })
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
