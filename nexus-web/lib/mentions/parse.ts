import type { MentionToken, MentionType } from "./types"

// The canonical token regex. Kept as a single source of truth.
//
// Examples matched:
//   @[arcology-project](operation:abc-123)
//   @[Q4 market sizing](record:0000-def)
//   @[acquisitions chat](conversation:xxxx)
//
// Intentionally strict on the type slug so it can't collide with URLs.
const TOKEN_RE = /@\[([^\]\n]+)\]\((operation|record|conversation|topic|agent):([a-zA-Z0-9_-]+)\)/g

export function extractMentions(text: string): MentionToken[] {
  if (!text) return []
  const out: MentionToken[] = []
  const seen = new Set<string>()  // dedupe by `type:id` so we don't fetch twice
  let m: RegExpExecArray | null
  // Reset lastIndex — TOKEN_RE is a shared global regex.
  TOKEN_RE.lastIndex = 0
  while ((m = TOKEN_RE.exec(text)) !== null) {
    const key = `${m[2]}:${m[3]}`
    if (seen.has(key)) continue
    seen.add(key)
    out.push({ label: m[1], type: m[2] as MentionType, id: m[3] })
  }
  return out
}

// Given raw message text, return an ordered list of parts — either plain text
// or a resolved token. Used by the message renderer.
export type MessagePart =
  | { kind: "text"; text: string }
  | { kind: "mention"; token: MentionToken }

export function splitByMentions(text: string): MessagePart[] {
  if (!text) return []
  const parts: MessagePart[] = []
  let last = 0
  let m: RegExpExecArray | null
  TOKEN_RE.lastIndex = 0
  while ((m = TOKEN_RE.exec(text)) !== null) {
    if (m.index > last) parts.push({ kind: "text", text: text.slice(last, m.index) })
    parts.push({ kind: "mention", token: { label: m[1], type: m[2] as MentionType, id: m[3] } })
    last = m.index + m[0].length
  }
  if (last < text.length) parts.push({ kind: "text", text: text.slice(last) })
  return parts
}

// Strip all tokens to a plain-text form (replacing `@[label](type:id)` with
// just `@label`). Useful for TTS, summarization, and preview snippets where
// the chip markup would be noise.
export function stripMentionsToPlain(text: string): string {
  if (!text) return text
  return text.replace(TOKEN_RE, (_, label) => `@${label}`)
}

// A sentinel we use while preprocessing markdown. The zero-width joiners at
// both ends make it extremely unlikely to collide with real content and
// invisible if it somehow ends up rendered. Sentinels are replaced back into
// real chips after ReactMarkdown has done its thing.
//
// Format: `\u200C[[MENTION:<b64(type:id:label)>]]\u200C`
export const MENTION_SENTINEL_OPEN = "\u200C[[MENTION:"
export const MENTION_SENTINEL_CLOSE = "]]\u200C"
const SENTINEL_RE = /\u200C\[\[MENTION:([A-Za-z0-9+/=]+)\]\]\u200C/g

function b64encode(s: string): string {
  if (typeof window === "undefined") return Buffer.from(s, "utf8").toString("base64")
  return btoa(unescape(encodeURIComponent(s)))
}
function b64decode(s: string): string {
  if (typeof window === "undefined") return Buffer.from(s, "base64").toString("utf8")
  return decodeURIComponent(escape(atob(s)))
}

// Replace tokens with sentinels so markdown won't reinterpret `@[x](y:z)` as
// a link. After render, callers split on SENTINEL_RE to swap in chips.
export function protectMentionsForMarkdown(text: string): string {
  if (!text) return text
  TOKEN_RE.lastIndex = 0
  return text.replace(TOKEN_RE, (_, label, type, id) => {
    const payload = b64encode(`${type}|${id}|${label}`)
    return `${MENTION_SENTINEL_OPEN}${payload}${MENTION_SENTINEL_CLOSE}`
  })
}

export type SentinelSplit =
  | { kind: "text"; text: string }
  | { kind: "mention"; token: MentionToken }

// Split a post-markdown string by the mention sentinels and decode each one.
export function splitBySentinels(text: string): SentinelSplit[] {
  if (!text) return []
  const parts: SentinelSplit[] = []
  let last = 0
  let m: RegExpExecArray | null
  SENTINEL_RE.lastIndex = 0
  while ((m = SENTINEL_RE.exec(text)) !== null) {
    if (m.index > last) parts.push({ kind: "text", text: text.slice(last, m.index) })
    try {
      const decoded = b64decode(m[1])
      const [type, id, ...labelParts] = decoded.split("|")
      const label = labelParts.join("|")
      if (type && id && label) {
        parts.push({ kind: "mention", token: { type: type as MentionType, id, label } })
      }
    } catch {
      // Swallow decode errors — fall through to text so nothing renders blank.
      parts.push({ kind: "text", text: m[0] })
    }
    last = m.index + m[0].length
  }
  if (last < text.length) parts.push({ kind: "text", text: text.slice(last) })
  return parts
}
