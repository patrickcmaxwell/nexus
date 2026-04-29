import { NextRequest, NextResponse } from 'next/server'
import { updateSession } from '@/lib/supabase/proxy'

export async function proxy(request: NextRequest): Promise<NextResponse> {
  return updateSession(request)
}

export const config = {
  matcher: [
    '/dashboard/:path*',
    '/api/eve/:path*',
    '/api/operations/:path*',
    '/api/agents/:path*',
    '/api/nexus-map/:path*',
  ],
}
