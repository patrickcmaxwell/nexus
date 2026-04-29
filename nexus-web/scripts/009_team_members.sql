-- ============================================================
-- Maxwell Nexus — Team Members
-- Multi-user support: each person gets their own identity,
-- PIN hash, face descriptor, and role.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.team_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('director', 'member', 'admin')),
  email TEXT,
  pin_hash TEXT NOT NULL,               -- bcrypt hash of their chosen PIN
  face_descriptor JSONB,                -- 128-float array (enrolled on first login or updated)
  seed_face_descriptor JSONB,           -- admin-uploaded descriptor for initial recognition
  avatar_url TEXT,
  status TEXT NOT NULL DEFAULT 'invited' CHECK (status IN ('invited', 'active', 'disabled')),
  invite_token TEXT UNIQUE,             -- one-time token for the invite link
  invited_by UUID REFERENCES public.team_members(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS team_members_status_idx ON public.team_members (status);
CREATE INDEX IF NOT EXISTS team_members_invite_token_idx ON public.team_members (invite_token) WHERE invite_token IS NOT NULL;

-- RLS — service role only writes; users can read their own row
ALTER TABLE public.team_members ENABLE ROW LEVEL SECURITY;

-- Allow anyone with a valid session to read active members (for display names etc.)
-- All mutations go through the service role API.

-- Update security_sessions to reference team_member_id
ALTER TABLE public.security_sessions ADD COLUMN IF NOT EXISTS team_member_id UUID REFERENCES public.team_members(id);
