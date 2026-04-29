-- Create missions table for user-saved missions
CREATE TABLE IF NOT EXISTS public.missions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  location TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('SUCCESS', 'FAILED', 'ONGOING')),
  threat_level TEXT NOT NULL CHECK (threat_level IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
  suit TEXT NOT NULL,
  summary TEXT NOT NULL,
  mission_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.missions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "missions_select_own" ON public.missions FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "missions_insert_own" ON public.missions FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "missions_update_own" ON public.missions FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "missions_delete_own" ON public.missions FOR DELETE USING (auth.uid() = user_id);

-- Create jarvis_history table for persisted JARVIS conversations
CREATE TABLE IF NOT EXISTS public.jarvis_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.jarvis_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "jarvis_select_own" ON public.jarvis_history FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "jarvis_insert_own" ON public.jarvis_history FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "jarvis_delete_own" ON public.jarvis_history FOR DELETE USING (auth.uid() = user_id);
