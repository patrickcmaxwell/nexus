-- Add parent_conversation_id to eve_conversations for sub-thread support
ALTER TABLE eve_conversations
  ADD COLUMN IF NOT EXISTS parent_conversation_id uuid
    REFERENCES eve_conversations(id)
    ON DELETE CASCADE;

-- Index for fast sub-thread lookups
CREATE INDEX IF NOT EXISTS idx_eve_conv_parent
  ON eve_conversations(parent_conversation_id)
  WHERE parent_conversation_id IS NOT NULL;
