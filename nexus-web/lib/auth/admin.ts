// Shared admin-gate for /api/admin/* routes. Any human with role='admin'
// OR is_owner=true counts as a "key holder" — they can lock other users,
// reset credentials, view audit logs. The owner is the root of trust;
// admins are deputized peers who provide redundancy if the owner is
// compromised or away.
//
// Why split this from getActiveHuman: routes outside /api/admin shouldn't
// gate by role. This helper centralizes the "is this caller a key holder"
// check so the same logic applies everywhere.
import { NextResponse } from "next/server"
import { getActiveHuman, type ActiveHuman } from "./session"
import { createClient } from "@supabase/supabase-js"

export type Admin = ActiveHuman

/// Returns the active human if they have admin privileges, OR a 401/403
/// response object the route should return immediately.
export async function requireAdmin(): Promise<{ admin: Admin } | { error: NextResponse }> {
  const human = await getActiveHuman()
  if (!human) {
    return { error: NextResponse.json({ error: "Not authenticated" }, { status: 401 }) }
  }
  if (human.role !== "admin" && !human.isOwner) {
    return { error: NextResponse.json({ error: "Admin access required" }, { status: 403 }) }
  }
  return { admin: human }
}

/// Service-role client used by admin routes to mutate other humans' rows.
/// Returned as a tiny helper so each route doesn't repeat the createClient
/// boilerplate.
export function getServiceClient() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { persistSession: false, autoRefreshToken: false } }
  )
}

/// Append an entry to security_log. Used by every admin action so there's
/// an immutable trail of who did what to whom and why. `event` is a stable
/// machine-readable key like "admin.lock_user"; `metadata` carries the
/// human-readable details (actor name, reason, target etc.).
export async function logAdminAction(opts: {
  event: string
  actorHumanId: string
  actorDisplayName: string
  targetHumanId?: string
  metadata?: Record<string, unknown>
}) {
  const supabase = getServiceClient()
  await supabase.from("security_log").insert({
    user_id: opts.targetHumanId ?? opts.actorHumanId,
    event: opts.event,
    metadata: {
      actorHumanId: opts.actorHumanId,
      actorDisplayName: opts.actorDisplayName,
      targetHumanId: opts.targetHumanId ?? null,
      ...(opts.metadata ?? {}),
    },
  })
}
