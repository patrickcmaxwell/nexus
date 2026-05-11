-- 025_session_device_metadata.sql
--
-- Capture device fingerprint at session creation so the user can tell
-- their iPhone from a stranger's laptop on the Sessions panel. Without
-- this, every row in the upcoming /dashboard/settings sessions list
-- looks identical ("face login, May 8") and the revoke button is
-- effectively blind — the whole point of self-serve session control
-- is being able to recognize *which* session you're killing.
--
-- All three columns are nullable so legacy rows (sessions minted before
-- this migration) keep working; the UI renders an "Unknown device" pill
-- for those and they age out as cookies expire.
--
-- Applied to prod via MCP; this file is the canonical record. Idempotent.

ALTER TABLE security_sessions
  ADD COLUMN IF NOT EXISTS user_agent TEXT;

ALTER TABLE security_sessions
  ADD COLUMN IF NOT EXISTS ip_address INET;

ALTER TABLE security_sessions
  ADD COLUMN IF NOT EXISTS device_label TEXT;

CREATE INDEX IF NOT EXISTS security_sessions_team_member_active_idx
  ON security_sessions (team_member_id, invalidated, expires_at);
