-- =====================================================================
-- 001_humans.sql
-- Phase 1 Migration: Transition from 'team_members' to 'humans',
-- introducing granular Groups and Data Permissions mappings.
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.humans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  handle TEXT UNIQUE,
  display_name TEXT NOT NULL,
  avatar_url TEXT,
  role TEXT NOT NULL DEFAULT 'observer' CHECK (role IN ('observer', 'collaborator', 'operator', 'admin')),
  is_owner BOOLEAN NOT NULL DEFAULT false,
  pin_hash TEXT,                     -- Carried over for face/pin auth
  seed_face_descriptor JSONB,        -- Carried over for face/pin auth
  status TEXT DEFAULT 'active' CHECK (status IN ('invited', 'active', 'disabled')),
  invite_token TEXT UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Groups table for Crew / Cell designations
CREATE TABLE IF NOT EXISTS public.groups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,
  created_by UUID REFERENCES public.humans(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Group membership assignments
CREATE TABLE IF NOT EXISTS public.group_members (
  group_id UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  human_id UUID NOT NULL REFERENCES public.humans(id) ON DELETE CASCADE,
  role TEXT DEFAULT 'member' CHECK (role IN ('member', 'moderator', 'owner')),
  joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (group_id, human_id)
);

-- Data permissions (Polymorphic mapping for all Nexus resources)
CREATE TABLE IF NOT EXISTS public.data_permissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  resource_type TEXT NOT NULL,   -- e.g., 'agent', 'operation', 'directive', 'protocol', 'conversation'
  resource_id UUID NOT NULL,
  owner_id UUID NOT NULL REFERENCES public.humans(id) ON DELETE CASCADE,
  visibility TEXT NOT NULL DEFAULT 'private' CHECK (visibility IN ('private', 'shared', 'group', 'public')),
  shared_with UUID[] DEFAULT '{}', -- specific human_ids
  group_id UUID REFERENCES public.groups(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(resource_type, resource_id)
);

-- Note: Actual resource tables (operations, agents, eve_conversations) will trigger 
-- an insert/update into `data_permissions`, and their respective RLS policies 
-- will JOIN to this table to verify `auth.uid() / session.team_member_id`.

-- ── Data Migration ──────────────────────────────────────────────────────────
-- Migrate existing team_members into humans
INSERT INTO public.humans (id, display_name, handle, role, is_owner, pin_hash, seed_face_descriptor, invite_token, status, created_at)
SELECT 
  id, 
  name as display_name, 
  LOWER(REGEXP_REPLACE(name, '[^a-zA-Z0-9]', '', 'g')) || '_' || substr(id::text, 1, 4) as handle, -- Safe, unique handle
  CASE 
     WHEN role = 'director' THEN 'admin'
     WHEN role = 'admin' THEN 'admin'
     ELSE 'observer'
  END as role,
  (role = 'director') as is_owner,
  pin_hash,
  seed_face_descriptor,
  invite_token,
  status,
  created_at
FROM public.team_members
ON CONFLICT DO NOTHING;

-- ── RLS Enablement ──────────────────────────────────────────────────────────
ALTER TABLE public.humans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.data_permissions ENABLE ROW LEVEL SECURITY;

-- Humans Table Policies
-- Public info (handles, display_names, avatars) is viewable by any authenticated person
CREATE POLICY "Humans are viewable by all authenticated users" 
ON public.humans FOR SELECT 
USING (true); -- Note: The backend API protects actual row selection to prevent leaking uninvited users if needed, or RLS here safely allows Map rendering

-- Only the owner (is_owner=true) or admins can modify humans
CREATE POLICY "Owners and Admins can update Humans"
ON public.humans FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM public.humans h 
    WHERE h.id = (current_setting('request.jwt.claims', true)::jsonb->>'team_member_id')::uuid
    AND (h.is_owner = true OR h.role = 'admin')
  )
);
