import {
  Provider, CreateTaskInput, UpdateTaskInput, TaskResult,
  TestConnectionInput, TestConnectionResult,
} from "./index"

// Notion provider.
//
// Tasks map to pages in a Notion database. The user picks a database, the
// connect form captures its ID + the canonical Title/Status property names.
// Why not assume "Title"/"Status" — Notion lets users rename properties,
// so we let them tell us what their column is called.
//
// API docs: https://developers.notion.com/reference

const API_BASE = "https://api.notion.com/v1"
const API_VERSION = "2022-06-28"

export const notion: Provider = {
  id: "notion",
  name: "Notion",
  description: "Drop tasks Eve creates into a Notion database — anything from a kanban board to a research log.",
  icon: "file-text",
  accent: "oklch(0.92 0.02 240)",   // Notion off-white

  connectFields: [
    {
      key: "integration_token",
      label: "Internal Integration Secret",
      placeholder: "secret_...",
      helperText: "From notion.so/my-integrations → New Integration. Then share your database with the integration.",
      required: true,
      secret: true,
      type: "password",
    },
    {
      key: "database_id",
      label: "Database ID",
      placeholder: "32-char hex (with or without dashes)",
      helperText: "Open your Notion database, copy the ID from the URL.",
      required: true,
      secret: false,
      type: "text",
    },
    {
      key: "title_property",
      label: "Title Property Name",
      placeholder: "Name",
      helperText: "Whatever your database calls the title column. Defaults to \"Name\" if your DB uses Notion's default.",
      required: false,
      secret: false,
      type: "text",
    },
    {
      key: "status_property",
      label: "Status Property Name",
      placeholder: "Status",
      helperText: "Status column name. Leave blank if your DB doesn't have one.",
      required: false,
      secret: false,
      type: "text",
    },
  ],

  async createTask({ connection, title, description, dueDate, priority }: CreateTaskInput): Promise<TaskResult> {
    const token = connection.credentials.access_token || connection.credentials.integration_token
    const databaseId = connection.config.database_id
    if (!token || !databaseId) {
      return { mocked: true, detail: "Notion credentials missing — task not created" }
    }

    const titleProperty = connection.config.title_property || "Name"
    const properties: Record<string, unknown> = {
      [titleProperty]: {
        title: [{ text: { content: title } }],
      },
    }

    // Status (optional, only added if the user named the property)
    const statusProp = connection.config.status_property
    if (statusProp) {
      properties[statusProp] = { status: { name: "Not started" } }
    }

    // Due date (best effort — Notion expects ISO YYYY-MM-DD or full ISO)
    if (dueDate) {
      properties["Due"] = { date: { start: dueDate.slice(0, 10) } }
    }

    // Priority via Notion select if the property exists. Notion will reject
    // unknown properties cleanly so we can attempt this without a probe.
    if (priority) {
      properties["Priority"] = { select: { name: capitalize(priority) } }
    }

    // Build children blocks for description (multi-paragraph)
    const children = description ? toParagraphBlocks(description) : undefined

    const res = await fetch(`${API_BASE}/pages`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Notion-Version": API_VERSION,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        parent: { database_id: databaseId },
        properties,
        ...(children ? { children } : {}),
      }),
    })

    if (!res.ok) {
      const detail = await res.text().catch(() => `HTTP ${res.status}`)
      throw new Error(`Notion createTask failed: ${detail.slice(0, 200)}`)
    }
    const json = await res.json() as { id: string; url?: string }
    return { externalId: json.id, url: json.url, mocked: false }
  },

  async testConnection({ values }: TestConnectionInput): Promise<TestConnectionResult> {
    const token = values.access_token || values.integration_token
    const databaseId = values.database_id
    if (!token) return { ok: false, detail: "Missing integration secret" }
    if (!databaseId) return { ok: false, detail: "Missing database ID" }
    try {
      // Notion has /users/me — cheapest probe; returns 200 with bot info
      // when the token is valid.
      const meRes = await fetch(`${API_BASE}/users/me`, {
        headers: { Authorization: `Bearer ${token}`, "Notion-Version": API_VERSION },
      })
      if (meRes.status === 401) return { ok: false, detail: "Integration secret rejected" }
      if (!meRes.ok) return { ok: false, detail: `Notion returned HTTP ${meRes.status}` }

      // Verify the database is reachable too — a common gotcha is forgetting
      // to share the database with the integration.
      const dbRes = await fetch(`${API_BASE}/databases/${databaseId.replace(/-/g, "")}`, {
        headers: { Authorization: `Bearer ${token}`, "Notion-Version": API_VERSION },
      })
      if (dbRes.status === 404) {
        return { ok: false, detail: "Database not found — share it with the integration in Notion" }
      }
      if (!dbRes.ok) return { ok: false, detail: `Database HTTP ${dbRes.status}` }
      const db = await dbRes.json() as { title?: Array<{ plain_text?: string }> }
      const dbName = db.title?.map((t) => t.plain_text ?? "").join("") || "the database"
      return { ok: true, detail: `Connected — ready to write to "${dbName}"` }
    } catch (err) {
      return { ok: false, detail: err instanceof Error ? err.message : "Network error" }
    }
  },

  async updateTask({ connection, externalId, status, comment }: UpdateTaskInput): Promise<TaskResult> {
    const token = connection.credentials.access_token || connection.credentials.integration_token
    if (!token) {
      return { externalId, mocked: true, detail: "Notion credentials missing — update skipped" }
    }

    if (status) {
      const statusProp = connection.config.status_property || "Status"
      const res = await fetch(`${API_BASE}/pages/${externalId}`, {
        method: "PATCH",
        headers: {
          Authorization: `Bearer ${token}`,
          "Notion-Version": API_VERSION,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          properties: { [statusProp]: { status: { name: status } } },
        }),
      })
      if (!res.ok) {
        const detail = await res.text().catch(() => `HTTP ${res.status}`)
        throw new Error(`Notion updateTask status failed: ${detail.slice(0, 200)}`)
      }
    }

    if (comment) {
      // Notion comments live on a separate endpoint
      const res = await fetch(`${API_BASE}/comments`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Notion-Version": API_VERSION,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          parent: { page_id: externalId },
          rich_text: [{ text: { content: comment } }],
        }),
      })
      if (!res.ok) {
        const detail = await res.text().catch(() => `HTTP ${res.status}`)
        throw new Error(`Notion comment failed: ${detail.slice(0, 200)}`)
      }
    }

    return { externalId, mocked: false }
  },
}

function capitalize(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1)
}

/// Split a string into Notion paragraph blocks. Notion caps rich_text per
/// block at 2000 characters, so we chunk to stay safe.
function toParagraphBlocks(text: string) {
  const lines = text.split(/\n\n+/)  // paragraph break = blank line
  return lines.flatMap((para) => {
    const chunks = chunkString(para, 1900)
    return chunks.map((chunk) => ({
      object: "block",
      type: "paragraph",
      paragraph: { rich_text: [{ type: "text", text: { content: chunk } }] },
    }))
  })
}

function chunkString(s: string, max: number): string[] {
  if (s.length <= max) return [s]
  const out: string[] = []
  for (let i = 0; i < s.length; i += max) {
    out.push(s.slice(i, i + max))
  }
  return out
}
