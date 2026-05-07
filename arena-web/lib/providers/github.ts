import {
  Provider, CreateTaskInput, UpdateTaskInput, TaskResult,
  TestConnectionInput, TestConnectionResult,
} from "./index"

// GitHub provider.
//
// Tasks → issues. Lets Eve file a real GitHub issue when you ask her to
// "open a bug to fix the login flow." Update path closes/reopens or adds
// a comment. Fine-grained PATs are recommended over classic tokens.
//
// API docs: https://docs.github.com/en/rest

const API_BASE = "https://api.github.com"
const API_VERSION = "2022-11-28"

export const github: Provider = {
  id: "github",
  name: "GitHub",
  description: "When Eve says \"file an issue,\" she opens a real GitHub issue in the repo you choose.",
  icon: "github",
  accent: "oklch(0.85 0.005 0)",   // GitHub off-white

  connectFields: [
    {
      key: "token",
      label: "Personal Access Token",
      placeholder: "github_pat_... or ghp_...",
      helperText: "Fine-grained PAT recommended. Needs `Issues: Read and write` permission on the target repo.",
      required: true,
      secret: true,
      type: "password",
    },
    {
      key: "repo",
      label: "Repository",
      placeholder: "owner/repo  (e.g. patrickcmaxwell/nexus)",
      helperText: "Default repo Eve files issues into. Override per-task by mentioning a different one.",
      required: true,
      secret: false,
      type: "text",
    },
    {
      key: "default_labels",
      label: "Default labels (comma-separated)",
      placeholder: "eve, automated",
      helperText: "Optional. Tags every issue Eve files so they're easy to filter.",
      required: false,
      secret: false,
      type: "text",
    },
  ],

  async testConnection({ values }: TestConnectionInput): Promise<TestConnectionResult> {
    const token = values.token
    const repo = values.repo
    if (!token) return { ok: false, detail: "Missing token" }
    if (!repo || !repo.includes("/")) return { ok: false, detail: "Repo must be in 'owner/repo' format" }

    try {
      // /user is the universal "is this token valid" probe
      const userRes = await fetch(`${API_BASE}/user`, {
        headers: ghHeaders(token),
      })
      if (userRes.status === 401) return { ok: false, detail: "Token rejected" }
      if (!userRes.ok) return { ok: false, detail: `GitHub returned HTTP ${userRes.status}` }
      const user = await userRes.json() as { login?: string }
      const who = user.login ?? "your account"

      // Verify the repo + issues permission by hitting the repo endpoint
      const repoRes = await fetch(`${API_BASE}/repos/${repo}`, {
        headers: ghHeaders(token),
      })
      if (repoRes.status === 404) return { ok: false, detail: `Repo ${repo} not found or token lacks access` }
      if (!repoRes.ok) return { ok: false, detail: `Repo HTTP ${repoRes.status}` }
      const repoJson = await repoRes.json() as { permissions?: { push?: boolean; pull?: boolean } }
      const perms = repoJson.permissions
      if (perms && !perms.pull) {
        return { ok: false, detail: `Token can see ${repo} but lacks read permission` }
      }
      return { ok: true, detail: `Connected as ${who} → ${repo}` }
    } catch (err) {
      return { ok: false, detail: err instanceof Error ? err.message : "Network error" }
    }
  },

  async createTask({ connection, title, description, priority }: CreateTaskInput): Promise<TaskResult> {
    const token = connection.credentials.token
    const repo = connection.config.repo
    if (!token || !repo) {
      return { mocked: true, detail: "GitHub credentials missing — issue not created" }
    }

    const body: Record<string, unknown> = { title }
    if (description) body.body = description

    const labels: string[] = []
    const defaults = (connection.config.default_labels || "")
      .split(",").map((s) => s.trim()).filter(Boolean)
    labels.push(...defaults)
    if (priority === "urgent" || priority === "high") {
      labels.push(`priority: ${priority}`)
    }
    if (labels.length > 0) body.labels = labels

    const res = await fetch(`${API_BASE}/repos/${repo}/issues`, {
      method: "POST",
      headers: { ...ghHeaders(token), "Content-Type": "application/json" },
      body: JSON.stringify(body),
    })
    if (!res.ok) {
      const detail = await res.text().catch(() => `HTTP ${res.status}`)
      throw new Error(`GitHub createIssue failed: ${detail.slice(0, 200)}`)
    }
    const issue = await res.json() as { number: number; html_url: string }
    return { externalId: String(issue.number), url: issue.html_url, mocked: false }
  },

  async updateTask({ connection, externalId, status, comment }: UpdateTaskInput): Promise<TaskResult> {
    const token = connection.credentials.token
    const repo = connection.config.repo
    if (!token || !repo) {
      return { externalId, mocked: true, detail: "GitHub credentials missing — update skipped" }
    }

    // Status mapping: GitHub issues are "open" or "closed". Anything that
    // looks like done/closed/complete maps to closed; anything else maps
    // to open. Lets Eve say "mark X as done" without knowing the GitHub
    // vocabulary.
    if (status) {
      const closed = /^(closed|done|complete|completed|resolved|fixed)$/i.test(status)
      const res = await fetch(`${API_BASE}/repos/${repo}/issues/${externalId}`, {
        method: "PATCH",
        headers: { ...ghHeaders(token), "Content-Type": "application/json" },
        body: JSON.stringify({ state: closed ? "closed" : "open" }),
      })
      if (!res.ok) {
        const detail = await res.text().catch(() => `HTTP ${res.status}`)
        throw new Error(`GitHub updateIssue state failed: ${detail.slice(0, 200)}`)
      }
    }

    if (comment) {
      const res = await fetch(`${API_BASE}/repos/${repo}/issues/${externalId}/comments`, {
        method: "POST",
        headers: { ...ghHeaders(token), "Content-Type": "application/json" },
        body: JSON.stringify({ body: comment }),
      })
      if (!res.ok) {
        const detail = await res.text().catch(() => `HTTP ${res.status}`)
        throw new Error(`GitHub addComment failed: ${detail.slice(0, 200)}`)
      }
    }

    return { externalId, mocked: false }
  },
}

function ghHeaders(token: string) {
  return {
    Authorization: `Bearer ${token}`,
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": API_VERSION,
  }
}
