-- Add scan scheduling to agents
-- scan_interval_hours: how often the cron job re-triggers this agent (default 12h)
ALTER TABLE public.agents ADD COLUMN IF NOT EXISTS scan_interval_hours INTEGER DEFAULT 12;
