-- Rename jarvis_history to eve_history and add conversation_id for grouping chats
ALTER TABLE public.jarvis_history RENAME TO eve_history;

-- Rename the policies to match the new table name
ALTER POLICY "jarvis_select_own" ON public.eve_history RENAME TO "eve_select_own";
ALTER POLICY "jarvis_insert_own" ON public.eve_history RENAME TO "eve_insert_own";
ALTER POLICY "jarvis_delete_own" ON public.eve_history RENAME TO "eve_delete_own";

-- Add conversation_id so we can group messages into sessions.
-- NULL is allowed so existing rows (which have no conversation yet) are not violated.
ALTER TABLE public.eve_history ADD COLUMN IF NOT EXISTS conversation_id UUID;

-- Add an index for fast per-conversation lookups
CREATE INDEX IF NOT EXISTS eve_history_conversation_idx ON public.eve_history (user_id, conversation_id, created_at);

-- Conversations table: one row per chat thread, stores title, source, timestamps
CREATE TABLE IF NOT EXISTS public.eve_conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL DEFAULT 'New Conversation',
  source TEXT NOT NULL DEFAULT 'maxwell' CHECK (source IN ('maxwell', 'grok', 'other')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.eve_conversations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "eve_conv_select_own" ON public.eve_conversations FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "eve_conv_insert_own" ON public.eve_conversations FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "eve_conv_update_own" ON public.eve_conversations FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "eve_conv_delete_own" ON public.eve_conversations FOR DELETE USING (auth.uid() = user_id);
