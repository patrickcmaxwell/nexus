// Heuristic classifier for Claude Code terminal snapshots.
//
// Given the last ~few-hundred-bytes of a PTY's scrollback, decide whether
// the session is in a state worth pinging the user about. Cheap pattern
// matching only — no LLM call. Returns null when nothing interesting is
// happening so the watcher can skip the push pipeline entirely.
//
// Why we look at only the tail of the snapshot: the buffer accumulates
// every command the session has run since it started. A `fatal:` that
// happened 30 minutes ago and was already fixed shouldn't re-page the
// user just because Lumen pushed an updated snapshot. The freshest few
// hundred chars tell us what's on screen NOW.

import crypto from "crypto"

export type AlertKind = "blocker" | "confirm" | "done" | "idle"

export interface Classification {
  kind: AlertKind
  /// Short fingerprint of the matched pattern. The watcher uses this to
  /// dedup: same kind + same signature = same condition, don't re-fire.
  signature: string
  /// ~200-char window around the matching text. Goes into the push body
  /// + watch log so the user can tell at a glance which session blew up.
  excerpt: string
}

// How much trailing snapshot text to inspect. Anything older is probably
// noise the user already read past. Tuned so a typical confirm prompt
// (the last line) plus a couple lines of context comfortably fit.
const TAIL_BYTES = 800

// How recently the snapshot must have been updated for `idle` to *not*
// fire. Above this, we treat the session as quiet.
const IDLE_AFTER_MS = 5 * 60 * 1000

interface Options {
  /// When did Lumen last push a snapshot for this session? Used to gate
  /// the "idle" classification — we only consider the session idle if
  /// nothing fresh has arrived in IDLE_AFTER_MS.
  lastSnapshotAt?: string | null
  /// Override `now()` for tests.
  now?: number
}

/// Run the heuristic chain. The order matters — blocker beats confirm
/// (a session that errored AND is now waiting on input gets paged as a
/// blocker, since that's the more urgent fix), confirm beats done,
/// done beats idle.
export function classify(snapshot: string | null, opts: Options = {}): Classification | null {
  if (!snapshot) return null
  const tail = snapshot.length > TAIL_BYTES ? snapshot.slice(-TAIL_BYTES) : snapshot
  const stripped = stripAnsi(tail)
  const lastNonEmpty = lastNonEmptyLine(stripped)

  // 1. Blocker / error patterns. Restricted to the tail so old errors
  //    that have scrolled out of attention don't re-fire.
  const errorMatch = matchAny(stripped, [
    /\berror:\s+(.{0,80})/i,
    /\bfatal:\s+(.{0,80})/i,
    /\bpanic:\s+(.{0,80})/i,
    /\bException:\s+(.{0,80})/,
    /\bFailed to\s+(.{0,80})/,
    /\bTraceback \(most recent call last\)/,
  ])
  if (errorMatch) {
    return {
      kind: "blocker",
      signature: sig("blocker", errorMatch.matched),
      excerpt: excerptAround(stripped, errorMatch.index),
    }
  }

  // 2. Waiting on confirmation. Anchored to the LAST non-empty line so
  //    we don't fire on a historical "(y/n)?" further up the scrollback.
  if (lastNonEmpty) {
    const confirmPattern = /(\(y\/n\)\??|\[Y\/n\]|\[y\/N\]|\(yes\/no\)|continue\?|proceed\?|are you sure\??|Press enter to continue)/i
    const m = lastNonEmpty.match(confirmPattern)
    if (m) {
      return {
        kind: "confirm",
        signature: sig("confirm", m[1]),
        excerpt: lastNonEmpty,
      }
    }
  }

  // 3. Done. Look for explicit success markers in the tail. We're
  //    deliberately conservative — only fire on phrases that strongly
  //    imply "the task wrapped" so we don't ping the user every time
  //    a step says "✓ installed".
  const doneMatch = matchAny(stripped, [
    /\bAll done!?\b/,
    /\bcompleted successfully\b/i,
    /\bfinished\s+in\s+[\d.]+\s*(s|sec|seconds|m|min)/i,
    /\bbuild\s+succeeded\b/i,
    /\bdeploy\s+(complete|completed|succeeded)\b/i,
    /^\s*✓\s+done\b/im,
  ])
  if (doneMatch) {
    return {
      kind: "done",
      signature: sig("done", doneMatch.matched),
      excerpt: excerptAround(stripped, doneMatch.index),
    }
  }

  // 4. Idle. Bare shell prompt at the bottom + no fresh snapshot for
  //    IDLE_AFTER_MS = "the session is quiet, probably done." Useful to
  //    catch the case where a long task finished but didn't print an
  //    obvious "done" marker.
  if (lastNonEmpty && IDLE_PROMPT_RE.test(lastNonEmpty)) {
    const lastTs = opts.lastSnapshotAt ? Date.parse(opts.lastSnapshotAt) : NaN
    const now = opts.now ?? Date.now()
    if (!Number.isNaN(lastTs) && now - lastTs >= IDLE_AFTER_MS) {
      return {
        kind: "idle",
        signature: sig("idle", lastNonEmpty),
        excerpt: lastNonEmpty,
      }
    }
  }

  return null
}

// MARK: - helpers

/// A bare shell prompt. Matches `$`, `#`, `>`, optionally preceded by
/// directory bits / user@host. Intentionally narrow so we don't flag a
/// `>` inside a markdown blockquote.
const IDLE_PROMPT_RE = /[$#%>]\s*$/

/// Strip ANSI color/cursor escape sequences so pattern matching doesn't
/// fight color codes. Doesn't try to handle every CSI in the spec —
/// just the common ones Claude Code outputs.
function stripAnsi(s: string): string {
  // eslint-disable-next-line no-control-regex
  return s.replace(/\[[0-9;?]*[a-zA-Z]/g, "").replace(/\r/g, "")
}

function lastNonEmptyLine(s: string): string | null {
  const lines = s.split("\n")
  for (let i = lines.length - 1; i >= 0; i--) {
    const l = lines[i].trim()
    if (l.length > 0) return l
  }
  return null
}

function matchAny(s: string, patterns: RegExp[]): { matched: string; index: number } | null {
  for (const p of patterns) {
    const m = p.exec(s)
    if (m) return { matched: m[0], index: m.index }
  }
  return null
}

/// 8-char stable hash of (kind + pattern text), trimmed so noisy variants
/// of the same condition collapse to the same signature.
function sig(kind: AlertKind, text: string): string {
  const normalized = text.toLowerCase().replace(/\s+/g, " ").trim().slice(0, 120)
  const hash = crypto.createHash("sha1").update(`${kind}:${normalized}`).digest("hex").slice(0, 10)
  return `${kind}:${hash}`
}

function excerptAround(s: string, index: number): string {
  const start = Math.max(0, index - 80)
  const end = Math.min(s.length, index + 200)
  return s.slice(start, end).trim().replace(/\n+/g, " ").slice(0, 240)
}

/// Stable hash of an entire snapshot. Used by the watcher to skip
/// re-classification when Lumen heartbeat-PATCHed without buffer changes.
export function snapshotHash(snapshot: string | null): string | null {
  if (!snapshot) return null
  return crypto.createHash("sha1").update(snapshot).digest("hex")
}
