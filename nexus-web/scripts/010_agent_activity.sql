-- Agent activity log — tracks what agents actually do
CREATE TABLE IF NOT EXISTS public.agent_activity (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  agent_id UUID REFERENCES public.agents(id) ON DELETE CASCADE,
  user_id UUID NOT NULL,
  action TEXT NOT NULL,  -- 'scan_started', 'finding_created', 'operation_created', 'scan_completed', 'error'
  details JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS agent_activity_agent_idx ON public.agent_activity (agent_id, created_at DESC);
CREATE INDEX IF NOT EXISTS agent_activity_user_idx ON public.agent_activity (user_id, created_at DESC);

-- Track last scan cursor so subsequent runs only process new content
ALTER TABLE public.agents ADD COLUMN IF NOT EXISTS last_scanned_at TIMESTAMPTZ;
ALTER TABLE public.agents ADD COLUMN IF NOT EXISTS total_findings INTEGER DEFAULT 0;
