CREATE TABLE IF NOT EXISTS eve_topics (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  conversation_id uuid NOT NULL REFERENCES eve_conversations(id) ON DELETE CASCADE,
  label text NOT NULL,
  description text NOT NULL DEFAULT '',
  color text NOT NULL DEFAULT 'cyan',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_eve_topics_conv ON eve_topics(conversation_id);

ALTER TABLE eve_topics ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'eve_topics' AND policyname = 'topics_select_own') THEN
    CREATE POLICY topics_select_own ON eve_topics FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'eve_topics' AND policyname = 'topics_insert_own') THEN
    CREATE POLICY topics_insert_own ON eve_topics FOR INSERT WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'eve_topics' AND policyname = 'topics_delete_own') THEN
    CREATE POLICY topics_delete_own ON eve_topics FOR DELETE USING (true);
  END IF;
END $$;
