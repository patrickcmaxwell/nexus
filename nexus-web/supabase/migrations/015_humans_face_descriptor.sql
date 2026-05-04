-- =====================================================================
-- 015_humans_face_descriptor.sql
-- 001_humans.sql migrated seed_face_descriptor over from team_members
-- but dropped the live face_descriptor column. The face route writes
-- enrolled descriptors to humans.face_descriptor, so without this
-- column enrollment silently no-ops and verify falls back to NO_REFERENCE
-- on every visit, breaking the face flow entirely.
-- =====================================================================

ALTER TABLE public.humans
  ADD COLUMN IF NOT EXISTS face_descriptor JSONB;

-- Backfill enrolled descriptors from the legacy team_members rows so
-- anyone who already enrolled before the humans migration doesn't have
-- to re-enroll. IDs were preserved 1:1 by 001_humans.sql.
UPDATE public.humans h
SET face_descriptor = tm.face_descriptor
FROM public.team_members tm
WHERE h.id = tm.id
  AND h.face_descriptor IS NULL
  AND tm.face_descriptor IS NOT NULL;
