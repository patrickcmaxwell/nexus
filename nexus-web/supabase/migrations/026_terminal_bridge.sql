-- 026_terminal_bridge.sql
--
-- Cross-device terminal control bridge. Lets the iOS Nexus app see and
-- control Claude Code terminal sessions that are actually running on
-- Lumen on the user's Mac. Without this bridge, terminal sessions are
-- Mac-local PTYs (SwiftTerm) and only the machine that spawned them can
-- see their output or send input — the phone is blind.
--
-- Architecture (deliberately polling, not realtime, for v1):
--   1. Lumen on the Mac spawns a CodeSession → POSTs a row into
--      terminal_sessions with status='running'.
--   2. Every 30s while running, Lumen PATCHes last_snapshot (buffer text)
--      + last_heartbeat_at. UI on iOS uses heartbeat staleness to mark a
--      session "stale" if Lumen crashes / sleeps.
--   3. iOS reads terminal_sessions to render a list, opens a row to view
--      the latest snapshot, and POSTs into terminal_commands to issue a
--      keystroke / command line.
--   4. Lumen polls terminal_commands every 5s for status='pending' rows
--      addressed to its sessions, .feed()s them into SwiftTerm, and
--      PATCHes status='dispatched'.
--   5. On exit, Lumen PATCHes terminal_sessions.status + ended_at.
--
-- Why not Supabase Realtime / SSE for v1: the iOS app already speaks the
-- nexus-web REST surface and has no streaming client. Polling at 5s is
-- "good enough" to feel responsive on a phone, and lets us ship the
-- end-to-end loop today. Realtime is a Phase 2b upgrade.
--
-- All rows are scoped to user_id; RLS would belong here but the project
-- pattern is to gate via service-role + getActiveAuthId() in the API
-- layer (same as schedules / operations / agents). Following that.
--
-- Idempotent. Applied via MCP after writing this file.

CREATE TABLE IF NOT EXISTS terminal_sessions (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             TEXT NOT NULL,
  mac_label           TEXT,                        -- e.g. "Patrick's MacBook Pro"
  folder              TEXT NOT NULL,               -- working directory the session was spawned in
  claude_path         TEXT,                        -- path to the claude binary used
  title               TEXT,                        -- session title (folder basename or PTY-reported)
  status              TEXT NOT NULL DEFAULT 'running',
                        -- 'running' | 'exited' | 'error' | 'stale'
  exit_code           INT,
  last_snapshot       TEXT,                        -- last buffer text Lumen pushed
  last_snapshot_at    TIMESTAMPTZ,
  last_heartbeat_at   TIMESTAMPTZ DEFAULT now(),   -- updated by Lumen heartbeat
  started_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  ended_at            TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS terminal_sessions_user_active_idx
  ON terminal_sessions (user_id, status, last_heartbeat_at DESC);

CREATE TABLE IF NOT EXISTS terminal_commands (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id      UUID NOT NULL REFERENCES terminal_sessions(id) ON DELETE CASCADE,
  user_id         TEXT NOT NULL,
  command         TEXT NOT NULL,                   -- raw bytes to feed into PTY (typically ending with \n)
  status          TEXT NOT NULL DEFAULT 'pending',
                    -- 'pending' | 'dispatched' | 'failed'
  failure_reason  TEXT,
  submitted_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  dispatched_at   TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS terminal_commands_pending_idx
  ON terminal_commands (session_id, status, submitted_at);

CREATE INDEX IF NOT EXISTS terminal_commands_user_idx
  ON terminal_commands (user_id, submitted_at DESC);
