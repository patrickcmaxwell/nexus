-- Operations: named missions/projects with objectives, status, priority
CREATE TABLE IF NOT EXISTS operations (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL,
  name          text NOT NULL,
  codename      text,
  description   text,
  objectives    text,
  status        text NOT NULL DEFAULT 'planning',   -- planning | active | paused | complete | aborted
  priority      text NOT NULL DEFAULT 'medium',     -- low | medium | high | critical
  directives    text,                               -- operation-specific rules for agents/Eve
  tags          text[] DEFAULT '{}',
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

-- Records attached to an operation (intel, findings, data, files, notes)
CREATE TABLE IF NOT EXISTS operation_records (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  operation_id  uuid NOT NULL REFERENCES operations(id) ON DELETE CASCADE,
  user_id       uuid NOT NULL,
  type          text NOT NULL DEFAULT 'note',        -- note | intel | data | finding | alert | file
  title         text NOT NULL,
  content       text,
  source        text,                                -- where it came from (Eve, agent name, manual)
  priority      text NOT NULL DEFAULT 'normal',      -- low | normal | high | critical
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- Operation ↔ Agent assignments
CREATE TABLE IF NOT EXISTS operation_agents (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  operation_id  uuid NOT NULL REFERENCES operations(id) ON DELETE CASCADE,
  agent_id      uuid NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
  role_in_op    text,                                -- what this agent is doing specifically
  assigned_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE(operation_id, agent_id)
);

-- RLS
ALTER TABLE operations        ENABLE ROW LEVEL SECURITY;
ALTER TABLE operation_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE operation_agents  ENABLE ROW LEVEL SECURITY;

CREATE POLICY ops_select_own   ON operations        FOR SELECT USING (user_id = auth.uid());
CREATE POLICY ops_insert_own   ON operations        FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY ops_update_own   ON operations        FOR UPDATE USING (user_id = auth.uid());
CREATE POLICY ops_delete_own   ON operations        FOR DELETE USING (user_id = auth.uid());

CREATE POLICY rec_select_own   ON operation_records FOR SELECT USING (user_id = auth.uid());
CREATE POLICY rec_insert_own   ON operation_records FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY rec_update_own   ON operation_records FOR UPDATE USING (user_id = auth.uid());
CREATE POLICY rec_delete_own   ON operation_records FOR DELETE USING (user_id = auth.uid());

CREATE POLICY oa_select_own    ON operation_agents  FOR SELECT USING (
  EXISTS (SELECT 1 FROM operations o WHERE o.id = operation_id AND o.user_id = auth.uid())
);
CREATE POLICY oa_insert_own    ON operation_agents  FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM operations o WHERE o.id = operation_id AND o.user_id = auth.uid())
);
CREATE POLICY oa_delete_own    ON operation_agents  FOR DELETE USING (
  EXISTS (SELECT 1 FROM operations o WHERE o.id = operation_id AND o.user_id = auth.uid())
);
