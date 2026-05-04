-- =====================================================================
-- 014_group_chat.sql
-- Group messaging layer — human-to-human chat within groups
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.group_messages (
  id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id    UUID         NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  human_id    UUID         NOT NULL REFERENCES public.humans(id) ON DELETE CASCADE,
  content     TEXT         NOT NULL,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS group_messages_group_created
  ON public.group_messages(group_id, created_at DESC);

ALTER TABLE public.group_messages ENABLE ROW LEVEL SECURITY;

-- Only group members can read messages
CREATE POLICY "group_messages_select"
ON public.group_messages FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.group_members
    WHERE group_id = group_messages.group_id
      AND human_id = (
        SELECT id FROM public.humans
        WHERE id = (
          SELECT team_member_id FROM public.security_sessions
          WHERE id = (current_setting('request.headers', true)::jsonb->>'x-nx-session')::uuid
            AND invalidated = false
            AND expires_at > now()
          LIMIT 1
        )
        LIMIT 1
      )
  )
);

-- Only group members can insert messages (as themselves)
CREATE POLICY "group_messages_insert"
ON public.group_messages FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.group_members
    WHERE group_id = group_messages.group_id
      AND human_id = group_messages.human_id
  )
);
