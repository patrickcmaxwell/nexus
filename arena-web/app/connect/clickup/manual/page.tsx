// /connect/clickup/manual
//
// Legacy fallback for when OAuth isn't available (e.g., admin hasn't
// registered the OAuth app yet). Reuses the existing generic ConnectForm
// which posts an API key + list id to /api/connections.

import Link from "next/link"
import { notFound, redirect } from "next/navigation"
import { getActiveHuman } from "@/lib/auth/session"
import { findProvider } from "@/lib/providers"
import ConnectForm from "../../[provider]/ConnectForm"

export const dynamic = "force-dynamic"

export default async function ManualClickUpPage() {
  const me = await getActiveHuman()
  if (!me) redirect("/")
  const provider = findProvider("clickup")
  if (!provider) notFound()

  return (
    <main className="min-h-screen px-4 sm:px-6 py-12 max-w-2xl mx-auto">
      <Link
        href="/connect/clickup"
        className="inline-flex items-center gap-2 text-sm text-[color:var(--color-fg-muted)] hover:text-[color:var(--color-fg)] mb-10"
      >
        ← Back to ClickUp
      </Link>

      <header className="mb-10">
        <p className="text-sm text-[color:var(--color-fg-subtle)] mb-2">Manual setup · ClickUp</p>
        <h1 className="text-3xl font-semibold tracking-tight">Paste an API token</h1>
        <p className="text-base text-[color:var(--color-fg-muted)] mt-3 max-w-lg leading-relaxed">
          For when OAuth isn&apos;t set up. Generate a personal token from ClickUp Settings → Apps and paste it below.
        </p>
      </header>

      <ConnectForm provider={{
        id: provider.id,
        name: provider.name,
        accent: provider.accent,
        connectFields: provider.connectFields,
      }} />
    </main>
  )
}
