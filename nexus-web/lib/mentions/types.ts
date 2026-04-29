// Shared types for the @mention system.
//
// Mention tokens are stored in plain text as `@[label](type:id)` — a format
// that round-trips cleanly through Supabase TEXT columns, through the xAI
// chat completions API, and through markdown rendering (with a preprocessing
// pass that protects the tokens from markdown link parsing).

export type MentionType =
  | "operation"
  | "record"
  | "conversation"
  | "topic"
  | "agent"

// What the search API returns for a single result row.
// `sublabel` is a short one-liner shown under the main label (e.g. the
// operation's codename, or a record's parent operation).
export type MentionResult = {
  type: MentionType
  id: string
  label: string        // Primary display name (e.g. "arcology-project")
  sublabel?: string    // Optional secondary line
  // Type-specific decoration hints — kept optional so the API can evolve.
  status?: string
  color?: string       // For topics
}

// What gets embedded in a message body as a token: `@[label](type:id)`
export type MentionToken = {
  type: MentionType
  id: string
  label: string
}

// Labels for picker headings.
export const MENTION_TYPE_LABELS: Record<MentionType, string> = {
  operation: "Operations",
  record: "Records",
  conversation: "Conversations",
  topic: "Topics",
  agent: "Agents",
}

// Color per type — used by chips and picker rows so you can tell at a glance
// what kind of thing you're mentioning. Kept in one place so we can retune.
export const MENTION_TYPE_COLORS: Record<MentionType, { fg: string; bg: string; border: string }> = {
  operation:    { fg: "rgb(251 191 36)",  bg: "rgba(251,191,36,0.10)",  border: "rgba(251,191,36,0.35)" },  // amber
  record:       { fg: "rgb(234 179 8)",   bg: "rgba(234,179,8,0.10)",   border: "rgba(234,179,8,0.35)" },   // yellow
  conversation: { fg: "rgb(167 139 250)", bg: "rgba(167,139,250,0.10)", border: "rgba(167,139,250,0.35)" }, // violet
  topic:        { fg: "rgb(52 211 153)",  bg: "rgba(52,211,153,0.10)",  border: "rgba(52,211,153,0.35)" },  // emerald
  agent:        { fg: "rgb(34 211 238)",  bg: "rgba(34,211,238,0.10)",  border: "rgba(34,211,238,0.35)" },  // cyan
}
