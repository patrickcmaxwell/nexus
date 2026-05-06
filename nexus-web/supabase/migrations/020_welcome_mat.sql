-- 020_welcome_mat.sql
--
-- Operation Welcome Mat — multi-frame face enrollment + avatar storage.
--
-- Applied directly to prod via MCP; this file is the canonical record so
-- a fresh environment can replay. Idempotent guards throughout.

-- 1. face_descriptors: array of 128-float vectors. Lets enrollment store
-- multiple angles (front/left/right/up/down) so verify can match against
-- any reference frame. Singular face_descriptor is kept as legacy fallback.
ALTER TABLE humans
  ADD COLUMN IF NOT EXISTS face_descriptors JSONB NOT NULL DEFAULT '[]'::jsonb;

-- 2. avatars storage bucket. Public read because avatar URLs are surfaced
-- in the team picker UI to anonymous lock-screen visitors. Writes happen
-- server-side via service role; no insert/update policy needed.
INSERT INTO storage.buckets (id, name, public)
  VALUES ('avatars', 'avatars', true)
  ON CONFLICT (id) DO NOTHING;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'avatars_public_read'
  ) THEN
    CREATE POLICY "avatars_public_read"
      ON storage.objects FOR SELECT
      USING (bucket_id = 'avatars');
  END IF;
END $$;
