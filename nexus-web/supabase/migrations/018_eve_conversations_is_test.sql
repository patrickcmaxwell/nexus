-- 018_eve_conversations_is_test.sql
--
-- Add is_test flag so smoke-test conversations don't pollute the chat sidebar.
-- Smoke-test runs (curl loops, automated QA) should set is_test=true on POST;
-- the GET handler at /api/eve/conversations now filters them out by default.
--
-- Backfill is a no-op because the three legacy test conversations
-- (sources: lumen-qa-fresh, qa-thread-test, floating) were deleted in
-- the same change that introduced this column.

alter table public.eve_conversations
  add column if not exists is_test boolean not null default false;

-- Index for the common query pattern: list real conversations for a user.
create index if not exists idx_eve_conversations_user_real
  on public.eve_conversations (user_id, updated_at desc)
  where is_test = false;
