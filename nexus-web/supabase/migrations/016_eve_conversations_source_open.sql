-- Drop the CHECK constraint on eve_conversations.source.
--
-- The original 002_rename_jarvis_to_eve.sql restricted source to
-- ('maxwell', 'grok', 'other'). Real callers now tag sources like
-- 'lumen', 'desktop', 'floating', 'local' — those silently fail the
-- INSERT and the route returns conversationId: null, breaking
-- conversation threading from non-web clients.
--
-- The column is descriptive metadata, not a strict enum, so the
-- constraint is dropped entirely. The DEFAULT 'maxwell' is preserved.

ALTER TABLE public.eve_conversations
  DROP CONSTRAINT IF EXISTS eve_conversations_source_check;
