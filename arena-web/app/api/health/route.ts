import { NextResponse } from "next/server"
import { ALL_PROVIDERS } from "@/lib/providers"

export const dynamic = "force-dynamic"

// GET /api/health — service alive + brief status. Surfaces which providers
// are registered so the dashboard can confirm its expectations match the
// deployed binary.
export async function GET() {
  const providers = ALL_PROVIDERS.map((p) => ({
    id: p.id,
    name: p.name,
    methods: [
      p.createTask  ? "createTask"  : null,
      p.updateTask  ? "updateTask"  : null,
      p.routePayment ? "routePayment" : null,
      p.syncPush    ? "syncPush"    : null,
    ].filter(Boolean),
  }))
  return NextResponse.json({
    ok: true,
    service: "arena-web",
    version: "0.1.0",
    providers,
    secretConfigured: !!process.env.ARENA_SECRET && process.env.ARENA_SECRET !== "dev-arena-secret-change-me",
    timestamp: new Date().toISOString(),
  })
}
