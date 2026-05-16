-- 028_terminal_watcher.sql
--
-- State table for the Eve terminal watcher. We need to track, per session,
-- (a) the snapshot we last evaluated so we don't re-classify identical text,
-- (b) what kind of alert (if any) we last fired so we can dedup "same
--     blocker is still blocking" into a single notification, and
-- (c) when we last alerted so we can rate-limit re-fires for the same
--     condition (the user doesn't want a buzz every minute that a session
--     is still waiting on `Continue? [y/N]`).
--
-- This table is keyed by session_id 1:1 with terminal_sessions. Could have
-- lived as columns on terminal_sessions itself, but keeping it separate
-- means the watcher's bookkeeping doesn't pollute the read-hot row that
-- Lumen heartbeats every 30s.

CREATE TABLE IF NOT EXISTS terminal_watch_state (
  session_id           UUID PRIMARY KEY REFERENCES terminal_sessions(id) ON DELETE CASCADE,
  user_id              TEXT NOT NULL,

  -- Hash of the snapshot we last evaluated. Skip re-evaluation when the
  -- snapshot hasn't moved since the last watcher pass.
  last_evaluated_hash  TEXT,
  last_evaluated_at    TIMESTAMPTZ,

  -- Last alert kind we fired ('blocker' | 'confirm' | 'done' | 'idle' | null)
  -- and the signature that triggered it. Signature is a short fingerprint
  -- of the matching pattern (e.g. "confirm:y/n" or "error:fatal"). When
  -- the same kind + signature recurs we suppress until cooldown elapses.
  last_alert_kind       TEXT,
  last_alert_signature  TEXT,
  last_alert_at         TIMESTAMPTZ,

  -- How many consecutive watcher passes have observed this same alert
  -- condition. We use this to backoff on repeat alerts — the user wants
  -- "you're blocked" once, not every minute.
  repeat_count          INT NOT NULL DEFAULT 0,

  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS terminal_watch_state_user_idx
  ON terminal_watch_state (user_id, updated_at DESC);

-- Append-only log of every alert the watcher actually fired. Useful for
-- "did Eve ping me when that build failed?" debugging without grepping
-- push_log.
CREATE TABLE IF NOT EXISTS terminal_watch_log (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id   UUID REFERENCES terminal_sessions(id) ON DELETE SET NULL,
  user_id      TEXT NOT NULL,
  alert_kind   TEXT NOT NULL,        -- blocker | confirm | done | idle
  signature    TEXT,                 -- short pattern key, e.g. "confirm:y/n"
  excerpt      TEXT,                 -- ~200-char window around the match
  push_result  JSONB,                -- {sent, skipped, failed} from sendPush
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS terminal_watch_log_user_idx
  ON terminal_watch_log (user_id, created_at DESC);
