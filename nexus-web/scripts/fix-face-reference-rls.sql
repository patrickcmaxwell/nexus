-- Add missing INSERT, UPDATE, DELETE policies for face_reference table
-- Drop existing policies first to avoid conflicts

DROP POLICY IF EXISTS face_ref_insert_own ON face_reference;
DROP POLICY IF EXISTS face_ref_update_own ON face_reference;
DROP POLICY IF EXISTS face_ref_delete_own ON face_reference;

-- Allow users to insert their own face reference
CREATE POLICY face_ref_insert_own ON face_reference
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Allow users to update their own face reference  
CREATE POLICY face_ref_update_own ON face_reference
  FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Allow users to delete their own face reference
CREATE POLICY face_ref_delete_own ON face_reference
  FOR DELETE
  USING (auth.uid() = user_id);
