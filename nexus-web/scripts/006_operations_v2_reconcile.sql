-- =====================================================================
-- Operations v2 reconcile — aligns schema with the code that reads it.
-- Adds convenience columns, relaxes NOT NULL where the app may pass null,
-- and normalizes the status column so "no status" is NULL, not 'none'.
-- =====================================================================

-- ── 1. Records status: use NULL as "no status" instead of 'none' ────────
-- Convert any existing 'none' values to NULL and drop the default so new
-- records without an explicit status come out NULL as the code expects.
UPDATE operation_records SET status = NULL WHERE status = 'none';
ALTER TABLE operation_records ALTER COLUMN status DROP DEFAULT;

-- ── 2. operation_briefs.generated_at for freshness display ──────────────
ALTER TABLE operation_briefs
  ADD COLUMN IF NOT EXISTS generated_at timestamp with time zone DEFAULT now();

UPDATE operation_briefs
SET generated_at = COALESCE(generated_at, updated_at, created_at, now())
WHERE generated_at IS NULL;

-- ── 3. research_jobs: convenience columns used by the runner ────────────
ALTER TABLE research_jobs
  ADD COLUMN IF NOT EXISTS progress_note text,
  ADD COLUMN IF NOT EXISTS assigned_to text DEFAULT 'eve',
  ADD COLUMN IF NOT EXISTS result_summary text,
  ADD COLUMN IF NOT EXISTS findings_count integer DEFAULT 0;

-- Allow research jobs to be queued without an explicit prompt — the
-- runner will fall back to the parent record's title + content.
ALTER TABLE research_jobs ALTER COLUMN prompt DROP NOT NULL;

-- Default status to 'queued' rather than 'pending' to match app semantics.
ALTER TABLE research_jobs ALTER COLUMN status SET DEFAULT 'queued';
UPDATE research_jobs SET status = 'queued' WHERE status = 'pending';

-- Default model to the reasoning model we actually use.
ALTER TABLE research_jobs ALTER COLUMN model SET DEFAULT 'grok-4-fast-reasoning';
