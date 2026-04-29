-- ============================================================
-- Maxwell Nexus — Security Tables
-- ============================================================

-- IP Blocklist: persisted blocked IPs after 5 failed PIN attempts
CREATE TABLE IF NOT EXISTS public.ip_blocklist (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ip TEXT NOT NULL UNIQUE,
  attempt_count INT NOT NULL DEFAULT 0,
  blocked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  unblocked_at TIMESTAMPTZ
);

-- No RLS on ip_blocklist — written only by server-side service role, never directly by users
ALTER TABLE public.ip_blocklist ENABLE ROW LEVEL SECURITY;
-- No SELECT policy = no user can read it via client


-- Security Audit Log: every PIN attempt, face check, lockout event
CREATE TABLE IF NOT EXISTS public.security_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  event TEXT NOT NULL,
  -- events: pin_attempt | pin_success | pin_fail | ip_blocked | face_enroll
  --         face_pass | face_fail | face_lock | logout_face_pass | logout_face_fail
  ip TEXT,
  metadata JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.security_log ENABLE ROW LEVEL SECURITY;
-- No user policies — written only via service role in API routes


-- Face Reference: stores the 128-float face descriptor enrolled at first PIN entry
CREATE TABLE IF NOT EXISTS public.face_reference (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,
  descriptor JSONB NOT NULL, -- array of 128 floats from face-api.js
  enrolled_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.face_reference ENABLE ROW LEVEL SECURITY;

-- Users can read their own face reference (to know if enrolled)
CREATE POLICY "face_ref_select_own" ON public.face_reference
  FOR SELECT USING (auth.uid() = user_id);

-- Insert/update done server-side only via service_role (no user insert policy)

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS face_reference_user_idx ON public.face_reference (user_id);
CREATE INDEX IF NOT EXISTS security_log_user_idx ON public.security_log (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ip_blocklist_ip_idx ON public.ip_blocklist (ip);
