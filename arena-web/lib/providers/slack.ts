import {
  Provider, CreateTaskInput, UpdateTaskInput, TaskResult,
  TestConnectionInput, TestConnectionResult,
} from "./index"

// Slack provider.
//
// Task semantics map loosely: createTask posts a structured message into
// a channel; updateTask threads a status comment under the original message
// (preferred) or edits the original. Useful for "Eve, post a reminder in
// #ops to follow up on the migration."
//
// Auth: Slack bot token (xoxb-...) from a custom app installed to the
// user's workspace. Bot needs `chat:write` + `chat:write.public` scopes.
//
// API docs: https://api.slack.com/web

const API_BASE = "https://slack.com/api"

export const slack: Provider = {
  id: "slack",
  name: "Slack",
  description: "When Eve posts a reminder or note, it lands in your Slack channel — not buried in a chat history.",
  icon: "message-square",
  accent: "oklch(0.65 0.22 320)",  // Slack purple-pink

  connectFields: [
    {
      key: "bot_token",
      label: "Bot User OAuth Token",
      placeholder: "xoxb-...",
      helperText: "From your Slack app → OAuth & Permissions. Needs chat:write (and chat:write.public for channels the bot isn't in).",
      required: true,
      secret: true,
      type: "password",
    },
    {
      key: "default_channel",
      label: "Default Channel",
      placeholder: "#nexus-eve  or  C0123456",
      helperText: "Where Eve drops messages by default. Either a channel name (with #) or a channel ID.",
      required: true,
      secret: false,
      type: "text",
    },
  ],

  async testConnection({ values }: TestConnectionInput): Promise<TestConnectionResult> {
    const token = values.bot_token
    if (!token) return { ok: false, detail: "Missing bot token" }
    if (!token.startsWith("xoxb-")) {
      return { ok: false, detail: "Doesn't look like a bot token (xoxb-...)" }
    }
    try {
      // /auth.test — Slack's universal "is this token valid" probe
      const res = await fetch(`${API_BASE}/auth.test`, {
        method: "POST",
        headers: { Authorization: `Bearer ${token}` },
      })
      if (!res.ok) return { ok: false, detail: `Slack returned HTTP ${res.status}` }
      const json = await res.json() as { ok: boolean; team?: string; user?: string; error?: string }
      if (!json.ok) return { ok: false, detail: `Slack: ${json.error ?? "auth failed"}` }
      return { ok: true, detail: `Connected to ${json.team} as @${json.user}` }
    } catch (err) {
      return { ok: false, detail: err instanceof Error ? err.message : "Network error" }
    }
  },

  async createTask({ connection, title, description, priority }: CreateTaskInput): Promise<TaskResult> {
    const token = connection.credentials.access_token || connection.credentials.bot_token
    const channel = connection.config.default_channel
    if (!token || !channel) {
      return { mocked: true, detail: "Slack credentials missing — message not sent" }
    }

    // Build a Block Kit message: emoji + title as a header, optional body
    // as a section. Priority maps to a colored emoji prefix.
    const emoji = priorityEmoji(priority)
    const blocks: Array<Record<string, unknown>> = [
      {
        type: "section",
        text: { type: "mrkdwn", text: `${emoji} *${escapeMrkdwn(title)}*` },
      },
    ]
    if (description) {
      blocks.push({
        type: "section",
        text: { type: "mrkdwn", text: escapeMrkdwn(description).slice(0, 3000) },
      })
    }
    blocks.push({
      type: "context",
      elements: [
        { type: "mrkdwn", text: ":robot_face: _Posted by Eve via Arena_" },
      ],
    })

    const res = await fetch(`${API_BASE}/chat.postMessage`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json; charset=utf-8",
      },
      body: JSON.stringify({
        channel,
        text: `${emoji} ${title}`,  // fallback for notifications
        blocks,
      }),
    })
    const json = await res.json() as { ok: boolean; ts?: string; channel?: string; error?: string }
    if (!json.ok) {
      throw new Error(`Slack postMessage failed: ${json.error ?? `HTTP ${res.status}`}`)
    }
    // Slack message permalinks need a separate API call to construct, but
    // the {channel}/{ts} pair is enough to reference the message later.
    const externalId = `${json.channel}/${json.ts}`
    return { externalId, mocked: false }
  },

  async updateTask({ connection, externalId, status, comment }: UpdateTaskInput): Promise<TaskResult> {
    const token = connection.credentials.access_token || connection.credentials.bot_token
    if (!token) {
      return { externalId, mocked: true, detail: "Slack credentials missing — update skipped" }
    }
    // externalId is "channel/ts" from createTask
    const [channel, ts] = externalId.split("/")
    if (!channel || !ts) {
      throw new Error("Invalid Slack message reference — expected 'channel/ts'")
    }

    if (comment) {
      // Reply in thread — non-destructive update pattern.
      const text = status ? `*Status: ${status}* — ${comment}` : comment
      const res = await fetch(`${API_BASE}/chat.postMessage`, {
        method: "POST",
        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json; charset=utf-8" },
        body: JSON.stringify({ channel, thread_ts: ts, text }),
      })
      const json = await res.json() as { ok: boolean; error?: string }
      if (!json.ok) throw new Error(`Slack thread reply failed: ${json.error}`)
    } else if (status) {
      // No comment, status only → react with an emoji.
      const emoji = statusEmoji(status)
      const res = await fetch(`${API_BASE}/reactions.add`, {
        method: "POST",
        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json; charset=utf-8" },
        body: JSON.stringify({ channel, timestamp: ts, name: emoji }),
      })
      const json = await res.json() as { ok: boolean; error?: string }
      // already_reacted is fine — idempotent semantics
      if (!json.ok && json.error !== "already_reacted") {
        throw new Error(`Slack reaction failed: ${json.error}`)
      }
    }

    return { externalId, mocked: false }
  },
}

function priorityEmoji(p?: "urgent" | "high" | "normal" | "low"): string {
  switch (p) {
    case "urgent": return ":rotating_light:"
    case "high":   return ":exclamation:"
    case "low":    return ":dotted_line_face:"
    default:       return ":memo:"
  }
}

function statusEmoji(status: string): string {
  const lower = status.toLowerCase()
  if (/done|complete|resolved|fixed|shipped/.test(lower))   return "white_check_mark"
  if (/blocked|stuck|stalled/.test(lower))                  return "no_entry"
  if (/in.?progress|active|working/.test(lower))            return "construction"
  if (/cancel|abandon|drop/.test(lower))                    return "x"
  return "eyes"  // default: "I see this"
}

/// Slack mrkdwn requires escaping &, <, > in user content.
function escapeMrkdwn(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}
