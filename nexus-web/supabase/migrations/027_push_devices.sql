-- Push notification device registry.
--
-- One row per (human, device) pair. Stores the platform token, the user-
-- supplied preferences (which event categories the device wants to hear
-- about), and bookkeeping for last-seen / failed-delivery cleanup.
--
-- We keep the schema platform-agnostic ("ios" today; "web", "macos",
-- "android" tomorrow) because Lumen + the web dashboard will want the
-- same delivery surface once Patrick wires those up.
--
-- Why per-device (and not per-user): if Patrick has the iPhone, an iPad,
-- and Lumen all wanting notifications, each has its own APNs token. A
-- single user_id can map to N rows.

create table if not exists public.push_devices (
  id uuid primary key default gen_random_uuid(),
  human_id uuid not null references public.humans(id) on delete cascade,
  platform text not null check (platform in ('ios', 'macos', 'web', 'android')),
  -- Provider token. APNs hex string for iOS/macOS; FCM token for android;
  -- endpoint URL (or VAPID subscription JSON) for web.
  token text not null,
  -- App bundle / channel scoping. Lets us send to the iOS app and Lumen
  -- through different APNs topics on the same row schema.
  bundle_id text,
  -- Device-supplied label so the user can recognize and revoke individual
  -- devices from settings ("iPhone 15", "Patrick's iPad", etc.).
  device_label text,

  -- Event preferences. Mirror the iOS toggles in Settings -> Notifications.
  -- NULL = default-on; we don't want a user who registers before tweaking
  -- preferences to silently miss everything.
  notify_agent_done boolean default true,
  notify_schedule_fired boolean default true,
  notify_research_done boolean default true,
  notify_op_updated boolean default false,
  notify_terminal_alert boolean default true,

  -- Bookkeeping
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  last_sent_at timestamptz,
  -- Streak of failed deliveries since the last success. When this crosses
  -- a threshold we prune the row, because either the token rotated or the
  -- user uninstalled the app and we'd be paying for dead pushes forever.
  consecutive_failures int not null default 0,
  last_error text,

  unique (human_id, token)
);

create index if not exists push_devices_human_id_idx on public.push_devices (human_id);
create index if not exists push_devices_last_seen_idx on public.push_devices (last_seen_at desc);

-- Append-only audit of what we attempted to deliver. Useful for "did Eve
-- ever try to notify me about that schedule firing?" debugging without
-- having to read APNs server logs.
create table if not exists public.push_log (
  id uuid primary key default gen_random_uuid(),
  device_id uuid references public.push_devices(id) on delete set null,
  human_id uuid references public.humans(id) on delete set null,
  event text not null,           -- agent.done | schedule.fired | research.done | op.updated | terminal.alert
  title text,
  body text,
  payload jsonb,
  status text not null,          -- sent | skipped | failed
  status_reason text,
  created_at timestamptz not null default now()
);

create index if not exists push_log_human_created_idx on public.push_log (human_id, created_at desc);
create index if not exists push_log_event_created_idx on public.push_log (event, created_at desc);
