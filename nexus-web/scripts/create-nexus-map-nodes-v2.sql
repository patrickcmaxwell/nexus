-- Drop and recreate with correct schema matching the API (label, tags)
drop table if exists public.nexus_map_nodes cascade;

create table public.nexus_map_nodes (
  id                     uuid primary key default gen_random_uuid(),
  user_id                uuid not null,
  label                  text not null,
  description            text default '',
  tags                   text[] default '{}',
  source_conversation_id uuid references public.eve_conversations(id) on delete set null,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

create index nexus_map_nodes_user_id_idx on public.nexus_map_nodes(user_id);

alter table public.nexus_map_nodes enable row level security;

-- Service role bypasses RLS, so a single permissive policy covers server-side inserts
create policy "map_nodes_service_all"
  on public.nexus_map_nodes for all
  using (true)
  with check (true);
