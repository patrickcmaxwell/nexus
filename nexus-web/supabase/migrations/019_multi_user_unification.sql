-- 019_multi_user_unification.sql
--
-- Operation Multi-User: unify identity on `humans`, drop the parallel
-- `team_members` table, add `email` as the identity primitive, bridge to
-- auth.users via `humans.auth_id`, lock down session table RLS.
--
-- This file captures schema changes that were applied directly to prod
-- via MCP during Operation Multi-User. Idempotent guards make it safe to
-- replay against a fresh environment.

-- 1. Add email column (the identity primitive that fixes PIN-collision)
ALTER TABLE humans ADD COLUMN IF NOT EXISTS email TEXT;

-- Case-insensitive unique index — same email cannot belong to two humans.
CREATE UNIQUE INDEX IF NOT EXISTS humans_email_lower_idx ON humans (lower(email));

-- 2. Backfill emails from team_members where ids match (one-time, may no-op)
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_schema='public' AND table_name='team_members') THEN
    UPDATE humans h
       SET email = tm.email
      FROM team_members tm
     WHERE h.id = tm.id AND h.email IS NULL AND tm.email IS NOT NULL;

    UPDATE humans h
       SET face_descriptor = tm.face_descriptor
      FROM team_members tm
     WHERE h.id = tm.id
       AND h.face_descriptor IS NULL
       AND tm.face_descriptor IS NOT NULL;
  END IF;
END $$;

-- 3. After backfill, email is required for any new human
ALTER TABLE humans ALTER COLUMN email SET NOT NULL;

-- 4. Bridge humans.id (identity) to auth.users.id (data ownership). All
-- user-scoped data tables (eve_history, operations, etc.) FK to auth.users,
-- so the session helper resolves session → human → auth_id when scoping
-- queries to the active user.
UPDATE humans h
   SET auth_id = u.id
  FROM auth.users u
 WHERE h.email = u.email
   AND h.auth_id IS NULL;

-- 5. Invalidate orphan sessions tied to the legacy hardcoded "director"
-- string and the orphan UUID baked into /api/security/pin's USER_ID const.
-- These were never linked to a real human; killing them = forced re-login.
UPDATE security_sessions
   SET invalidated = true
 WHERE user_id IN ('director', 'e9d9a15b-0e5a-4631-9b50-6225ee03a44f');

-- 6. Repoint security_sessions.team_member_id FK from team_members → humans.
-- Same id space, so no row-level fixup needed beyond the constraint swap.
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint
             WHERE conname='security_sessions_team_member_id_fkey'
               AND conrelid='public.security_sessions'::regclass) THEN
    ALTER TABLE security_sessions
      DROP CONSTRAINT security_sessions_team_member_id_fkey;
  END IF;
END $$;
ALTER TABLE security_sessions
  ADD CONSTRAINT security_sessions_team_member_id_fkey
  FOREIGN KEY (team_member_id) REFERENCES humans(id) ON DELETE CASCADE;

-- 7. Drop legacy tables
DROP TABLE IF EXISTS team_members;
DROP TABLE IF EXISTS face_reference;

-- 8. Lock down security_sessions: anon should never read/write session rows.
-- Service-role API routes bypass RLS by capability so backend keeps working;
-- enabling RLS with no policies = anon-blocked, which is what we want for
-- a secrets-bearing table.
ALTER TABLE security_sessions ENABLE ROW LEVEL SECURITY;
