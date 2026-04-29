-- Eve Directives & Protocols
-- Directives are hard rules Eve follows in all conversations.
-- Protocols define how Eve interacts with specific systems.

create table if not exists public.eve_directives (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  type        text not null check (type in ('directive', 'protocol')),
  title       text not null,
  content     text not null,
  is_active   boolean not null default true,
  priority    integer not null default 0,  -- higher = injected first in system prompt
  target      text,                        -- for protocols: which system (e.g. 'operations', 'agents', 'map', 'all')
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- RLS
alter table public.eve_directives enable row level security;

create policy "directives_select_own" on public.eve_directives
  for select using (auth.uid() = user_id);

create policy "directives_insert_own" on public.eve_directives
  for insert with check (auth.uid() = user_id);

create policy "directives_update_own" on public.eve_directives
  for update using (auth.uid() = user_id);

create policy "directives_delete_own" on public.eve_directives
  for delete using (auth.uid() = user_id);

-- Updated_at trigger
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger eve_directives_updated_at
  before update on public.eve_directives
  for each row execute function public.set_updated_at();

-- Seed default directives for the Director
-- These will be inserted by the app on first load if none exist,
-- using the service role to bypass RLS.
