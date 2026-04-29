-- Eve Memory Bank
-- Stores persistent facts, tasks, objectives and conversation summaries
-- that are injected into every Eve session so she never forgets.

CREATE TABLE IF NOT EXISTS public.eve_memory (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL,
  type        text NOT NULL CHECK (type IN ('fact', 'task', 'objective', 'summary', 'preference')),
  content     text NOT NULL,
  source      text,           -- 'user' | 'eve' | 'auto_summary'
  is_active   boolean NOT NULL DEFAULT true,
  priority    integer NOT NULL DEFAULT 5,  -- 1 (highest) to 10 (lowest)
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

-- Index for fast retrieval per user
CREATE INDEX IF NOT EXISTS eve_memory_user_idx ON public.eve_memory (user_id, is_active, priority);

-- RLS
ALTER TABLE public.eve_memory ENABLE ROW LEVEL SECURITY;

CREATE POLICY eve_memory_select_own ON public.eve_memory
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY eve_memory_insert_own ON public.eve_memory
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY eve_memory_update_own ON public.eve_memory
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY eve_memory_delete_own ON public.eve_memory
  FOR DELETE USING (auth.uid() = user_id);

-- Conversation summary tracking: mark conversations as summarized
ALTER TABLE public.eve_history
  ADD COLUMN IF NOT EXISTS summarized boolean NOT NULL DEFAULT false;
