// Cron parsing helpers built on `cron-parser` (v5).
//
// We parse twice — once to validate input on insert/update (so the user
// gets a 400 with a real reason instead of a runtime crash later), and
// once at fire time to compute the NEXT next_run_at after a successful
// firing. Both go through the same cron-parser API.
//
// Timezones are IANA strings (e.g., "America/Chicago"). cron-parser handles
// DST transitions correctly when a tz is provided.

import { CronExpressionParser } from "cron-parser"

export type CronValidation =
  | { ok: true }
  | { ok: false; reason: string }

export function validateCron(expression: string, tz?: string): CronValidation {
  const expr = (expression ?? "").trim()
  if (!expr) return { ok: false, reason: "expression required" }
  try {
    CronExpressionParser.parse(expr, tz ? { tz } : undefined)
    return { ok: true }
  } catch (err) {
    return { ok: false, reason: err instanceof Error ? err.message : "invalid cron expression" }
  }
}

// Compute the next firing time strictly AFTER the given anchor (defaults
// to "now"). Used (a) on schedule insert to set the initial next_run_at
// and (b) by the runner immediately after firing to roll forward.
export function nextRunAt(
  expression: string,
  tz: string,
  after: Date = new Date(),
): Date {
  const interval = CronExpressionParser.parse(expression, {
    tz,
    currentDate: after,
  })
  const next = interval.next()
  // CronDate.toDate() returns a real Date for further math/serialization.
  return next.toDate()
}

// Best-effort human label. Without a heavyweight dep like `cronstrue`,
// we map a few common patterns and fall back to the raw expression.
export function humanize(expression: string): string {
  const expr = expression.trim()
  const map: Record<string, string> = {
    "* * * * *":         "every minute",
    "*/5 * * * *":       "every 5 minutes",
    "*/15 * * * *":      "every 15 minutes",
    "0 * * * *":         "hourly (top of hour)",
    "0 0 * * *":         "daily at midnight",
    "0 9 * * *":         "daily at 9:00 AM",
    "0 17 * * *":        "daily at 5:00 PM",
    "0 9 * * 1-5":       "weekdays at 9:00 AM",
    "0 9 * * 1":         "Mondays at 9:00 AM",
    "0 0 1 * *":         "first of every month",
    "@hourly":           "hourly (top of hour)",
    "@daily":            "daily at midnight",
    "@weekly":           "weekly (Sunday midnight)",
    "@monthly":          "first of every month",
  }
  return map[expr] || expr
}
