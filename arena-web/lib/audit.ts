import { getServiceClient } from "@/lib/supabase/service"

// Best-effort audit log writer. Mirrors the existing arena_action_log
// schema (created in nexus-web migration 017) so the dashboard widget +
// /api/arena/log endpoint keep working without changes.

export type AuditCaller = "eve" | "lumen" | "ios" | "manual" | "system"

export type AuditEntry = {
  action: string                        // "task/create" | "task/update" | "payment/route" | "sync/push"
  caller?: AuditCaller
  payload?: Record<string, unknown>
  result?: Record<string, unknown>
  status?: "success" | "error"
  errorMsg?: string
}

export async function writeAudit(entry: AuditEntry): Promise<void> {
  const supabase = getServiceClient()
  try {
    await supabase
      .from("arena_action_log")
      .insert({
        action:    entry.action,
        caller:    entry.caller ?? "system",
        payload:   entry.payload ?? {},
        result:    entry.result ?? {},
        status:    entry.status ?? "success",
        error_msg: entry.errorMsg ?? null,
      })
  } catch {
    // Swallow — auditing failures must not bring the executor down. The
    // dashboard widget will simply show an empty log row for that action.
  }
}
