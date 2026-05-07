import {
  Provider, CreateTaskInput, UpdateTaskInput, TaskResult,
  TestConnectionInput, TestConnectionResult,
} from "./index"

// ClickUp provider.
//
// First concrete integration. Sets the pattern every other provider follows:
//   - `connectFields` declares what to ask for in the UI
//   - methods read from `connection.credentials` / `connection.config` per call
//   - mock fallback when credentials missing (Eve still works in dev)
//
// API docs: https://clickup.com/api

const API_BASE = "https://api.clickup.com/api/v2"

export const clickup: Provider = {
  id: "clickup",
  name: "ClickUp",
  description: "Send tasks Eve creates straight to your ClickUp lists.",
  icon: "list-checks",
  accent: "oklch(0.78 0.18 265)",  // ClickUp purple

  connectFields: [
    {
      key: "api_key",
      label: "Personal API Token",
      placeholder: "pk_...",
      helperText: "From ClickUp → Settings → Apps → API Token. Never shared.",
      required: true,
      secret: true,
      type: "password",
    },
    {
      key: "default_list_id",
      label: "Default List ID",
      placeholder: "901234567",
      helperText: "Where Eve drops tasks unless she specifies otherwise. Find it in the URL of any list.",
      required: true,
      secret: false,
      type: "text",
    },
  ],

  async createTask({ connection, title, description, dueDate, priority }: CreateTaskInput): Promise<TaskResult> {
    const apiKey = connection.credentials.api_key
    const listId = connection.config.default_list_id
    if (!apiKey || !listId) {
      return { mocked: true, detail: "ClickUp credentials missing — task not created" }
    }

    const body: Record<string, unknown> = { name: title }
    if (description) body.description = description
    if (dueDate) {
      const ms = Date.parse(dueDate)
      if (!isNaN(ms)) body.due_date = ms
    }
    if (priority) {
      body.priority = priorityCode(priority)
    }

    const res = await fetch(`${API_BASE}/list/${listId}/task`, {
      method: "POST",
      headers: {
        Authorization: apiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    })

    if (!res.ok) {
      const detail = await res.text().catch(() => `HTTP ${res.status}`)
      throw new Error(`ClickUp createTask failed: ${detail.slice(0, 200)}`)
    }
    const json = await res.json() as { id: string; url: string }
    return { externalId: json.id, url: json.url, mocked: false }
  },

  async testConnection({ values }: TestConnectionInput): Promise<TestConnectionResult> {
    const apiKey = values.api_key
    const listId = values.default_list_id
    if (!apiKey) return { ok: false, detail: "Missing API token" }
    // GET /user is the canonical "is this token valid" probe — single
    // round-trip, returns 200 with user info or 401.
    try {
      const userRes = await fetch(`${API_BASE}/user`, {
        headers: { Authorization: apiKey },
      })
      if (userRes.status === 401) return { ok: false, detail: "Token rejected — double-check it" }
      if (!userRes.ok) return { ok: false, detail: `ClickUp returned HTTP ${userRes.status}` }
      const user = await userRes.json() as { user?: { username?: string } }
      const who = user.user?.username ?? "your account"
      // Verify the list ID too if provided — tasks fail later if it's wrong.
      if (listId) {
        const listRes = await fetch(`${API_BASE}/list/${listId}`, {
          headers: { Authorization: apiKey },
        })
        if (!listRes.ok) {
          return { ok: false, detail: `Token works for ${who}, but list ${listId} isn't reachable` }
        }
      }
      return { ok: true, detail: `Connected as ${who}` }
    } catch (err) {
      return { ok: false, detail: err instanceof Error ? err.message : "Network error" }
    }
  },

  async updateTask({ connection, externalId, status, comment }: UpdateTaskInput): Promise<TaskResult> {
    const apiKey = connection.credentials.api_key
    if (!apiKey) {
      return { externalId, mocked: true, detail: "ClickUp credentials missing — update skipped" }
    }

    if (status) {
      const res = await fetch(`${API_BASE}/task/${externalId}`, {
        method: "PUT",
        headers: { Authorization: apiKey, "Content-Type": "application/json" },
        body: JSON.stringify({ status }),
      })
      if (!res.ok) {
        const detail = await res.text().catch(() => `HTTP ${res.status}`)
        throw new Error(`ClickUp updateTask status failed: ${detail.slice(0, 200)}`)
      }
    }

    if (comment) {
      const res = await fetch(`${API_BASE}/task/${externalId}/comment`, {
        method: "POST",
        headers: { Authorization: apiKey, "Content-Type": "application/json" },
        body: JSON.stringify({ comment_text: comment }),
      })
      if (!res.ok) {
        const detail = await res.text().catch(() => `HTTP ${res.status}`)
        throw new Error(`ClickUp comment failed: ${detail.slice(0, 200)}`)
      }
    }

    return { externalId, mocked: false }
  },
}

function priorityCode(p: "urgent" | "high" | "normal" | "low"): number {
  switch (p) {
    case "urgent": return 1
    case "high":   return 2
    case "normal": return 3
    case "low":    return 4
  }
}
