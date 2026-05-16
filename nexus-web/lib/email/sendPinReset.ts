// Self-service "I forgot my PIN" email. Mirrors sendInviteEmail in shape so
// the failure modes and env requirements are consistent. The link is the
// SAME shape as an invite link (/invite/[token]) because the reset path uses
// the existing invite-token flow — set a new PIN, optionally re-enroll face.
//
// Env:
//   RESEND_API_KEY  — required to actually send. Without it, the route still
//                     creates the reset token and returns 200, but the email
//                     part returns { sent:false, reason:"…" } so the UI can
//                     fall back to "ask an admin" copy.
//   RESEND_FROM     — optional sender override.

import { Resend } from "resend"

export type PinResetEmailResult =
  | { sent: true; id: string }
  | { sent: false; reason: string }

export async function sendPinResetEmail(opts: {
  to: string
  displayName: string
  resetUrl: string
}): Promise<PinResetEmailResult> {
  const apiKey = process.env.RESEND_API_KEY
  if (!apiKey) return { sent: false, reason: "RESEND_API_KEY not configured" }

  const from = process.env.RESEND_FROM || "Nexus <onboarding@resend.dev>"
  const subject = "Reset your Nexus PIN"

  const html = renderHtml(opts)
  const text = renderText(opts)

  try {
    const resend = new Resend(apiKey)
    const result = await resend.emails.send({ from, to: opts.to, subject, html, text })
    if (result.error) return { sent: false, reason: result.error.message ?? "send failed" }
    return { sent: true, id: result.data?.id ?? "" }
  } catch (e: any) {
    return { sent: false, reason: e?.message ?? String(e) }
  }
}

function renderHtml(opts: { displayName: string; resetUrl: string }): string {
  return `<!DOCTYPE html>
<html>
<head><meta charset="utf-8" /><meta name="viewport" content="width=device-width" /></head>
<body style="margin:0;padding:0;background:#0a0a14;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;color:#e5e5ec;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#0a0a14;padding:40px 20px;">
    <tr><td align="center">
      <table role="presentation" width="520" cellpadding="0" cellspacing="0" border="0" style="background:#13131f;border:1px solid #26263a;border-radius:14px;overflow:hidden;">
        <tr><td style="padding:32px 36px 12px 36px;">
          <div style="font-family:Menlo,Monaco,monospace;font-size:10px;letter-spacing:3px;color:#8b5cf6;text-transform:uppercase;margin-bottom:6px;">Nexus // Reset</div>
          <h1 style="margin:0 0 6px 0;font-size:22px;font-weight:600;color:#f5f5f9;">PIN reset, ${escapeHtml(opts.displayName)}.</h1>
          <p style="margin:8px 0 0 0;color:#a0a0b8;font-size:14px;line-height:1.5;">
            Someone (likely you) requested to reset your Nexus PIN. Click the button below to choose a new one.
          </p>
        </td></tr>
        <tr><td style="padding:18px 36px 8px 36px;">
          <a href="${opts.resetUrl}" style="display:inline-block;background:#8b5cf6;color:#ffffff;text-decoration:none;padding:12px 22px;border-radius:8px;font-size:13px;font-weight:600;letter-spacing:0.5px;">
            Reset PIN →
          </a>
          <p style="margin:14px 0 0 0;color:#71718a;font-size:11px;line-height:1.6;">
            This link is one-time use. If you didn't ask for this, ignore the email — your current PIN keeps working until you use the link.
          </p>
        </td></tr>
        <tr><td style="padding:24px 36px 28px 36px;border-top:1px solid #26263a;">
          <p style="margin:0;color:#71718a;font-size:11px;line-height:1.6;">
            If the button doesn't work, copy this URL into your browser:
            <br/><span style="color:#a0a0b8;word-break:break-all;font-family:Menlo,monospace;font-size:10px;">${opts.resetUrl}</span>
          </p>
          <p style="margin:14px 0 0 0;color:#4a4a60;font-size:10px;letter-spacing:1px;">NEXUS — PERSONAL AI OS</p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`
}

function renderText(opts: { displayName: string; resetUrl: string }): string {
  return [
    `Hi ${opts.displayName},`,
    "",
    "Someone requested to reset your Nexus PIN.",
    "Open this link to choose a new one:",
    opts.resetUrl,
    "",
    "If you didn't ask for this, ignore the email — your current PIN keeps working until you use the link.",
    "",
    "— Nexus",
  ].join("\n")
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
}
