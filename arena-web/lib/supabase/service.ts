import { createClient, SupabaseClient } from "@supabase/supabase-js"

// Lazy singleton — building the client at module load time would crash any
// route during Next's build-time page-data collection (no env vars there).
let cached: SupabaseClient | null = null

export function getServiceClient(): SupabaseClient {
  if (cached) return cached
  cached = createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { persistSession: false, autoRefreshToken: false } }
  )
  return cached
}
