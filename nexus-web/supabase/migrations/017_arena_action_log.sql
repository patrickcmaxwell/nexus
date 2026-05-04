-- Arena action audit log.
--
-- Every action Arena executes (task create, payment route, sync push, etc.)
-- writes a row here for auditability. Eve calls Arena via tool calls; this
-- table is the only persistent record of what was actually done.

CREATE TABLE IF NOT EXISTS public.arena_action_log (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  action      text NOT NULL,                            -- e.g. "task/create", "payment/route"
  caller      text,                                      -- "eve", "lumen", "ios", "manual"
  payload     jsonb NOT NULL DEFAULT '{}'::jsonb,
  result      jsonb NOT NULL DEFAULT '{}'::jsonb,
  status      text  NOT NULL DEFAULT 'success',          -- "success" | "error"
  error_msg   text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_arena_action_log_created_at
  ON public.arena_action_log (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_arena_action_log_action
  ON public.arena_action_log (action);

-- RLS off — Arena writes via the service role key. Reads happen from
-- nexus-web routes that already auth.
ALTER TABLE public.arena_action_log ENABLE ROW LEVEL SECURITY;
