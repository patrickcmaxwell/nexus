-- Nexus Map: custom topic nodes Eve can add during conversations
create table if not exists public.nexus_map_nodes (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null,
  title       text not null,
  description text,
  keywords    text[] default '{}',
  node_type   text not null default 'topic', -- topic | insight | reference
  source_conversation_id uuid references public.eve_conversations(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table public.nexus_map_nodes enable row level security;

create policy "map_nodes_select_own" on public.nexus_map_nodes for select using (user_id = auth.uid());
create policy "map_nodes_insert_own" on public.nexus_map_nodes for insert with check (user_id = auth.uid());
create policy "map_nodes_update_own" on public.nexus_map_nodes for update using (user_id = auth.uid());
create policy "map_nodes_delete_own" on public.nexus_map_nodes for delete using (user_id = auth.uid());
