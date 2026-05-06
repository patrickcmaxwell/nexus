import { Resend } from "resend"

/// Sends the invite email when an admin adds a new human via /api/team/invite.
/// Falls back gracefully when RESEND_API_KEY isn't configured — the route
/// still creates the humans row + invite_token, the inviter just has to
/// copy/paste the URL manually (legacy behavior). This way local dev and
/// non-Resend deploys keep working.
///
/// Env vars:
///   RESEND_API_KEY   — required for actual sending. From Resend dashboard.
///   RESEND_FROM      — optional sender. Defaults to onboarding@resend.dev
///                      (Resend's free shared sender — works without owning
///                      a verified domain). Override once a domain is set up.
export type InviteEmailResult =
  | { sent: true; id: string }
  | { sent: false; reason: string }

export async function sendInviteEmail(opts: {
  to: string
  inviteeName: string
  inviterName: string
  inviterEmail: string
  inviteUrl: string
  role: string
}): Promise<InviteEmailResult> {
  const apiKey = process.env.RESEND_API_KEY
  if (!apiKey) {
    return { sent: false, reason: "RESEND_API_KEY not configured" }
  }

  const from = process.env.RESEND_FROM || "Nexus <onboarding@resend.dev>"
  const subject = `${opts.inviterName} invited you to Nexus`

  const html = renderHtml(opts)
  const text = renderText(opts)

  try {
    const resend = new Resend(apiKey)
    const result = await resend.emails.send({
      from,
      to: opts.to,
      subject,
      html,
      text,
      replyTo: opts.inviterEmail,
    })
    if (result.error) {
      return { sent: false, reason: result.error.message ?? "send failed" }
    }
    return { sent: true, id: result.data?.id ?? "" }
  } catch (e: any) {
    return { sent: false, reason: e?.message ?? String(e) }
  }
}

// MARK: - Templates

/// Plain HTML — Nexus styling, no external assets so it renders well in
/// every email client (Gmail, Apple Mail, Outlook). Uses inline styles
/// because most clients strip <style> blocks.
function renderHtml(opts: {
  inviteeName: string
  inviterName: string
  inviteUrl: string
  role: string
}): string {
  const role = opts.role.toUpperCase()
  return `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width" />
</head>
<body style="margin:0;padding:0;background:#0a0a14;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;color:#e5e5ec;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#0a0a14;padding:40px 20px;">
    <tr><td align="center">
      <table role="presentation" width="520" cellpadding="0" cellspacing="0" border="0" style="background:#13131f;border:1px solid #26263a;border-radius:14px;overflow:hidden;">
        <tr><td style="padding:32px 36px 12px 36px;">
          <div style="font-family:Menlo,Monaco,monospace;font-size:10px;letter-spacing:3px;color:#8b5cf6;text-transform:uppercase;margin-bottom:6px;">Nexus // Invitation</div>
          <h1 style="margin:0 0 6px 0;font-size:22px;font-weight:600;color:#f5f5f9;">Welcome, ${escapeHtml(opts.inviteeName)}.</h1>
          <p style="margin:8px 0 0 0;color:#a0a0b8;font-size:14px;line-height:1.5;">
            ${escapeHtml(opts.inviterName)} invited you to join the team as
            <strong style="color:#c4b5fd;">${escapeHtml(role)}</strong>.
          </p>
        </td></tr>

        <tr><td style="padding:18px 36px 8px 36px;">
          <a href="${opts.inviteUrl}" style="display:inline-block;background:#8b5cf6;color:#ffffff;text-decoration:none;padding:12px 22px;border-radius:8px;font-size:13px;font-weight:600;letter-spacing:0.5px;">
            Set up your access →
          </a>
          <p style="margin:14px 0 0 0;color:#71718a;font-size:11px;line-height:1.6;">
            This link is one-time use. You'll set your PIN and (optionally) enroll your face for biometric sign-in. Takes about 60 seconds.
          </p>
        </td></tr>

        <tr><td style="padding:24px 36px 28px 36px;border-top:1px solid #26263a;">
          <p style="margin:0;color:#71718a;font-size:11px;line-height:1.6;">
            If the button doesn't work, copy this URL into your browser:
            <br/><span style="color:#a0a0b8;word-break:break-all;font-family:Menlo,monospace;font-size:10px;">${opts.inviteUrl}</span>
          </p>
          <p style="margin:14px 0 0 0;color:#4a4a60;font-size:10px;letter-spacing:1px;">
            NEXUS — PERSONAL AI OS
          </p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`
}

/// Plain-text fallback for email clients that block HTML.
function renderText(opts: {
  inviteeName: string
  inviterName: string
  inviteUrl: string
  role: string
}): string {
  return [
    `${opts.inviterName} invited you to Nexus.`,
    "",
    `Hi ${opts.inviteeName},`,
    "",
    `You've been invited as ${opts.role.toUpperCase()}. Set up your access here:`,
    opts.inviteUrl,
    "",
    "This link is one-time use. You'll set your PIN and optionally enroll your face for biometric sign-in.",
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
    .replace(/'/g, "&#039;")
}
