-- Security sessions table: server-side session store for face/passphrase auth
-- Each successful auth creates a row. Proxy validates against this table.
-- Sessions expire after 60 minutes of inactivity (refreshed on each valid request).

CREATE TABLE IF NOT EXISTS security_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_verified_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '60 minutes'),
  auth_method TEXT NOT NULL DEFAULT 'face', -- 'face' | 'passphrase'
  invalidated BOOLEAN NOT NULL DEFAULT false
);

-- Index for fast lookup by session id
CREATE INDEX IF NOT EXISTS security_sessions_id_idx ON security_sessions (id);

-- Auto-cleanup old sessions (older than 24h)
CREATE INDEX IF NOT EXISTS security_sessions_expires_idx ON security_sessions (expires_at);
