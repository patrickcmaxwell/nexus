-- =====================================================================
-- Operations v2 — records get lifecycle, nesting, briefs, and research
-- =====================================================================

-- ── 1. Extend operation_records ─────────────────────────────────────────
ALTER TABLE operation_records
  ADD COLUMN IF NOT EXISTS status text DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS pinned boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS archived_at timestamp with time zone,
  ADD COLUMN IF NOT EXISTS parent_record_id uuid REFERENCES operation_records(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS source_conversation_id uuid,
  ADD COLUMN IF NOT EXISTS source_message_id uuid,
  ADD COLUMN IF NOT EXISTS updated_at timestamp with time zone DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_records_parent        ON operation_records(parent_record_id);
CREATE INDEX IF NOT EXISTS idx_records_op_created    ON operation_records(operation_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_records_op_pinned     ON operation_records(operation_id, pinned) WHERE pinned = true;
CREATE INDEX IF NOT EXISTS idx_records_op_archived   ON operation_records(operation_id, archived_at);

-- ── 2. Operation briefs (Eve bulk output) ────────────────────────────────
-- kind: brief | actions | contradictions | themes | next_steps
CREATE TABLE IF NOT EXISTS operation_briefs (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  operation_id uuid NOT NULL REFERENCES operations(id) ON DELETE CASCADE,
  user_id      uuid NOT NULL,
  kind         text NOT NULL,
  content      text NOT NULL DEFAULT '',
  metadata     jsonb DEFAULT '{}'::jsonb,
  created_at   timestamp with time zone DEFAULT now(),
  updated_at   timestamp with time zone DEFAULT now(),
  UNIQUE (operation_id, kind)
);

ALTER TABLE operation_briefs ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_briefs_op   ON operation_briefs(operation_id);
CREATE INDEX IF NOT EXISTS idx_briefs_user ON operation_briefs(user_id);

-- ── 3. Research jobs ────────────────────────────────────────────────────
-- status: pending | running | completed | failed | cancelled
CREATE TABLE IF NOT EXISTS research_jobs (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  record_id       uuid NOT NULL REFERENCES operation_records(id) ON DELETE CASCADE,
  operation_id    uuid NOT NULL REFERENCES operations(id) ON DELETE CASCADE,
  user_id         uuid NOT NULL,
  status          text NOT NULL DEFAULT 'pending',
  prompt          text NOT NULL,
  model           text DEFAULT 'grok-3-mini',
  progress_notes  jsonb DEFAULT '[]'::jsonb,
  result          text,
  result_record_ids uuid[] DEFAULT ARRAY[]::uuid[],
  error           text,
  started_at      timestamp with time zone,
  completed_at    timestamp with time zone,
  created_at      timestamp with time zone DEFAULT now()
);

ALTER TABLE research_jobs ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_research_record   ON research_jobs(record_id);
CREATE INDEX IF NOT EXISTS idx_research_op       ON research_jobs(operation_id);
CREATE INDEX IF NOT EXISTS idx_research_status   ON research_jobs(status);
CREATE INDEX IF NOT EXISTS idx_research_user     ON research_jobs(user_id);

-- ── 4. Backfill updated_at for existing records ─────────────────────────
UPDATE operation_records
SET updated_at = COALESCE(updated_at, created_at)
WHERE updated_at IS NULL;
