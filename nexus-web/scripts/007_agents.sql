-- Create agents table
create table if not exists public.agents (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  name          text not null,
  codename      text,
  role          text not null default 'analyst',   -- analyst | collector | monitor | executor | comms
  status        text not null default 'standby',   -- standby | active | suspended | retired
  personality   text,                              -- personality description / voice
  capabilities  text[],                            -- array of capability tags
  directives    text,                              -- operational directives specific to this agent
  system_prompt text,                              -- full prompt injected when this agent runs
  avatar_color  text default '#00d4ff',
  last_deployed_at timestamp with time zone,
  created_at    timestamp with time zone default now(),
  updated_at    timestamp with time zone default now()
);

-- RLS
alter table public.agents enable row level security;

create policy "agents_select_own" on public.agents
  for select using (auth.uid() = user_id);

create policy "agents_insert_own" on public.agents
  for insert with check (auth.uid() = user_id);

create policy "agents_update_own" on public.agents
  for update using (auth.uid() = user_id);

create policy "agents_delete_own" on public.agents
  for delete using (auth.uid() = user_id);

-- Updated at trigger
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;

drop trigger if exists agents_updated_at on public.agents;
create trigger agents_updated_at
  before update on public.agents
  for each row execute procedure public.set_updated_at();
