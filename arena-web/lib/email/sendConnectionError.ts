import { Resend } from "resend"

// sendConnectionErrorEmail
//
// Notifies the user when an Arena connection flips to errored — usually
// because their token was revoked or rotated upstream. One email, with the
// rotation link. Throttled by `arena_connections.error_notified_at` (24h
// minimum gap) to prevent spam loops if a flaky provider keeps cycling.
//
// Falls back gracefully when RESEND_API_KEY is unset (returns
// `{ sent: false, reason }` so callers can log and move on without
// blocking the executor request).
//
// Env vars:
//   RESEND_API_KEY   — required for actual sending
//   RESEND_FROM      — optional, defaults to onboarding@resend.dev
//   ARENA_BASE_URL   — used to build the rotation link

export type EmailResult =
  | { sent: true; id: string }
  | { sent: false; reason: string }

export async function sendConnectionErrorEmail(opts: {
  to: string
  recipientName: string
  provider: string
  connectionLabel: string | null
  errorReason: string
  connectionId: string
}): Promise<EmailResult> {
  const apiKey = process.env.RESEND_API_KEY
  if (!apiKey) return { sent: false, reason: "RESEND_API_KEY not configured" }

  const from = process.env.RESEND_FROM || "Arena <onboarding@resend.dev>"
  const arenaBase = process.env.ARENA_BASE_URL || "https://arena-web-green.vercel.app"
  const rotateUrl = `${arenaBase}/connect/${opts.provider}/${opts.connectionId}/edit`

  const providerName = capitalize(opts.provider)
  const subject = `Your ${providerName} connection needs attention`
  const labelSuffix = opts.connectionLabel ? ` (${opts.connectionLabel})` : ""

  const html = renderHtml({
    recipientName: opts.recipientName,
    providerName,
    labelSuffix,
    errorReason: opts.errorReason,
    rotateUrl,
  })
  const text = renderText({
    recipientName: opts.recipientName,
    providerName,
    labelSuffix,
    errorReason: opts.errorReason,
    rotateUrl,
  })

  try {
    const resend = new Resend(apiKey)
    const result = await resend.emails.send({ from, to: opts.to, subject, html, text })
    if (result.error) return { sent: false, reason: result.error.message ?? "send failed" }
    return { sent: true, id: result.data?.id ?? "" }
  } catch (err) {
    return { sent: false, reason: err instanceof Error ? err.message : "send failed" }
  }
}

function capitalize(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1)
}

type TemplateInput = {
  recipientName: string
  providerName: string
  labelSuffix: string
  errorReason: string
  rotateUrl: string
}

function renderHtml(t: TemplateInput): string {
  // Plain HTML, no framework — runs anywhere.
  const safeReason = escapeHtml(t.errorReason).slice(0, 300)
  return `<!doctype html>
<html><body style="margin:0;background:#0a0c11;color:#e8e9ee;font-family:-apple-system,Segoe UI,system-ui,sans-serif;padding:24px;">
  <div style="max-width:560px;margin:0 auto;padding:32px;background:#10131a;border:1px solid #1f242e;border-radius:8px;">
    <p style="font-family:ui-monospace,SF Mono,monospace;font-size:11px;letter-spacing:3px;text-transform:uppercase;color:#8b5cf6;margin:0 0 8px 0;">Arena</p>
    <h1 style="font-size:20px;margin:0 0 16px 0;color:#ffffff;">Your ${escapeHtml(t.providerName)} connection${escapeHtml(t.labelSuffix)} needs attention</h1>
    <p style="font-size:14px;line-height:1.5;color:#b0b3bc;margin:0 0 16px 0;">Hi ${escapeHtml(t.recipientName)},</p>
    <p style="font-size:14px;line-height:1.5;color:#b0b3bc;margin:0 0 16px 0;">
      Eve tried to use your ${escapeHtml(t.providerName)} connection and the provider rejected the call. Most likely the token was rotated, expired, or revoked upstream.
    </p>
    <div style="padding:12px 16px;background:#1a0e0e;border:1px solid #4a1f1f;border-radius:6px;margin:0 0 24px 0;">
      <p style="font-family:ui-monospace,SF Mono,monospace;font-size:11px;color:#ef4444;margin:0 0 4px 0;">ERROR</p>
      <p style="font-size:13px;color:#fda4af;margin:0;font-family:ui-monospace,SF Mono,monospace;">${safeReason}</p>
    </div>
    <p style="font-size:14px;line-height:1.5;color:#b0b3bc;margin:0 0 24px 0;">
      Drop in a fresh token to get Eve back online — takes about 30 seconds.
    </p>
    <a href="${t.rotateUrl}" style="display:inline-block;padding:12px 24px;background:#8b5cf6;color:#ffffff;text-decoration:none;font-family:ui-monospace,SF Mono,monospace;font-size:11px;letter-spacing:2px;text-transform:uppercase;border-radius:6px;">
      Rotate Credentials →
    </a>
    <p style="font-size:11px;color:#5a5e68;margin:32px 0 0 0;">
      Until then, Eve will fall back to safe-mock mode for ${escapeHtml(t.providerName)} calls — actions will appear in your audit log with a yellow "mocked" badge instead of running for real.
    </p>
  </div>
  <p style="text-align:center;font-family:ui-monospace,SF Mono,monospace;font-size:9px;letter-spacing:2px;text-transform:uppercase;color:#3f4350;margin:16px 0 0 0;">
    Arena · Powered by Nexus
  </p>
</body></html>`
}

function renderText(t: TemplateInput): string {
  return `Your ${t.providerName} connection${t.labelSuffix} needs attention

Hi ${t.recipientName},

Eve tried to use your ${t.providerName} connection and the provider rejected the call. Most likely the token was rotated, expired, or revoked upstream.

ERROR: ${t.errorReason.slice(0, 300)}

Drop in a fresh token to get Eve back online:
${t.rotateUrl}

Until then, Eve will fall back to safe-mock mode for ${t.providerName} calls.
`
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
}
