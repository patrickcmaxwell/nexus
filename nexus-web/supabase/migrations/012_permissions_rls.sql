-- =====================================================================
-- 012_permissions_rls.sql
-- Enforcing Private, Shared, Group, and Public visibility via
-- Row Level Security acting alongside the data_permissions table.
-- =====================================================================

-- 1. Helper function to rapidly fetch current human_id based on Auth
CREATE OR REPLACE FUNCTION public.get_current_human_id() RETURNS uuid AS $$
  SELECT id FROM public.humans WHERE auth_id = auth.uid() LIMIT 1;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- 2. data_permissions RLS
ALTER TABLE public.data_permissions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "data_permissions_select" ON public.data_permissions FOR SELECT USING (
  owner_id = public.get_current_human_id()
  OR visibility = 'public'
  OR (visibility = 'shared' AND public.get_current_human_id() = ANY(shared_with))
  OR (visibility = 'group' AND EXISTS (
      SELECT 1 FROM public.group_members 
      WHERE group_id = data_permissions.group_id 
      AND human_id = public.get_current_human_id()
  ))
);

-- Only owners (or systemic admins) can mutate access mappings
CREATE POLICY "data_permissions_mutations" ON public.data_permissions FOR ALL USING (
  owner_id = public.get_current_human_id()
  OR EXISTS (SELECT 1 FROM public.humans WHERE id = public.get_current_human_id() AND role = 'admin')
);

-- 3. Operations Mapping
ALTER TABLE public.operations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "operations_select_rls" ON public.operations FOR SELECT USING (
  user_id = auth.uid() -- Backwards compatibility for single-user core
  OR EXISTS (
    SELECT 1 FROM public.data_permissions dp
    WHERE dp.resource_type = 'operation' 
    AND dp.resource_id = operations.id
    AND (
      dp.owner_id = public.get_current_human_id()
      OR dp.visibility = 'public'
      OR (dp.visibility = 'shared' AND public.get_current_human_id() = ANY(dp.shared_with))
      OR (dp.visibility = 'group' AND EXISTS (
          SELECT 1 FROM public.group_members gm 
          WHERE gm.group_id = dp.group_id AND gm.human_id = public.get_current_human_id()
      ))
    )
  )
);

CREATE POLICY "operations_update_rls" ON public.operations FOR UPDATE USING (
  user_id = auth.uid()
  OR EXISTS (
    SELECT 1 FROM public.data_permissions dp
    WHERE dp.resource_type = 'operation' 
    AND dp.resource_id = operations.id
    AND dp.owner_id = public.get_current_human_id()
  )
);

-- 4. Agents Mapping
ALTER TABLE public.agents ENABLE ROW LEVEL SECURITY;

CREATE POLICY "agents_select_rls" ON public.agents FOR SELECT USING (
  user_id = auth.uid()
  OR EXISTS (
    SELECT 1 FROM public.data_permissions dp
    WHERE dp.resource_type = 'agent' 
    AND dp.resource_id = agents.id
    AND (
      dp.owner_id = public.get_current_human_id()
      OR dp.visibility = 'public'
      OR (dp.visibility = 'shared' AND public.get_current_human_id() = ANY(dp.shared_with))
      OR (dp.visibility = 'group' AND EXISTS (
          SELECT 1 FROM public.group_members gm 
          WHERE gm.group_id = dp.group_id AND gm.human_id = public.get_current_human_id()
      ))
    )
  )
);

CREATE POLICY "agents_update_rls" ON public.agents FOR UPDATE USING (
  user_id = auth.uid()
  OR EXISTS (
    SELECT 1 FROM public.data_permissions dp
    WHERE dp.resource_type = 'agent' 
    AND dp.resource_id = agents.id
    AND dp.owner_id = public.get_current_human_id()
  )
);
