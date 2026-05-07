-- 001_arena_connections.sql
--
-- Per-human external service connections. The credentials column stores
-- whatever the provider needs (API token, OAuth refresh token, etc.) as
-- JSONB so each provider can shape its own payload. Service-role only
-- access; clients never read this table directly.

CREATE TABLE IF NOT EXISTS arena_connections (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    provider      TEXT NOT NULL,                   -- 'clickup' | 'stripe' | etc.
    label         TEXT,                            -- user-given name ("Personal ClickUp", "Work Stripe")
    credentials   JSONB NOT NULL DEFAULT '{}'::jsonb,
    config        JSONB NOT NULL DEFAULT '{}'::jsonb,  -- non-secret per-provider settings
    status        TEXT NOT NULL DEFAULT 'active',  -- 'active' | 'errored' | 'disabled'
    last_used_at  TIMESTAMPTZ,
    last_error    TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, provider, label)
);

CREATE INDEX IF NOT EXISTS idx_arena_connections_user
    ON arena_connections (user_id, provider);

ALTER TABLE arena_connections ENABLE ROW LEVEL SECURITY;
-- No policies: service-role only. The Arena server reads + writes via the
-- service-role key. Users interact through the Arena web UI which uses
-- service-role + scopes by user_id from the validated session.

-- Reuse arena_action_log from migration 017 — Arena Web writes to the same
-- table so the existing dashboard widget keeps working.
