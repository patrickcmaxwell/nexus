import { createClient } from "@supabase/supabase-js"

// Service role client — bypasses RLS. Only use server-side in API routes.
export function createServiceClient() {
  const secretKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_SECRET_KEY;
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    secretKey!,
    { auth: { persistSession: false } }
  )
}
