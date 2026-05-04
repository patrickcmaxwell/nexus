import { NextRequest, NextResponse } from 'next/server'
import { updateSession } from '@/lib/supabase/proxy'

const DESKTOP_ORIGIN = 'http://localhost:5173'

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': DESKTOP_ORIGIN,
  'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Lumen-Client',
  'Access-Control-Allow-Credentials': 'true',
}

export async function proxy(request: NextRequest): Promise<NextResponse> {
  const origin = request.headers.get('origin')

  if (request.method === 'OPTIONS' && origin === DESKTOP_ORIGIN) {
    return new NextResponse(null, { status: 200, headers: CORS_HEADERS })
  }

  const res = await updateSession(request)

  if (origin === DESKTOP_ORIGIN) {
    Object.entries(CORS_HEADERS).forEach(([k, v]) => res.headers.set(k, v))
  }

  return res
}

export const config = {
  matcher: [
    '/dashboard/:path*',
    '/api/:path*',
  ],
}
