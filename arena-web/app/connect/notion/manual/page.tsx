// /connect/notion/manual — legacy fallback for Internal Integration secret.
import Link from "next/link"
import { notFound, redirect } from "next/navigation"
import { getActiveHuman } from "@/lib/auth/session"
import { findProvider } from "@/lib/providers"
import ConnectForm from "../../[provider]/ConnectForm"

export const dynamic = "force-dynamic"

export default async function ManualNotionPage() {
  const me = await getActiveHuman()
  if (!me) redirect("/")
  const provider = findProvider("notion")
  if (!provider) notFound()

  return (
    <main className="min-h-screen px-4 sm:px-6 py-12 max-w-2xl mx-auto">
      <Link
        href="/connect/notion"
        className="inline-flex items-center gap-2 text-sm text-[color:var(--color-fg-muted)] hover:text-[color:var(--color-fg)] mb-10"
      >
        ← Back to Notion
      </Link>

      <header className="mb-10">
        <p className="text-sm text-[color:var(--color-fg-subtle)] mb-2">Manual setup · Notion</p>
        <h1 className="text-3xl font-semibold tracking-tight">Paste an integration secret</h1>
        <p className="text-base text-[color:var(--color-fg-muted)] mt-3 max-w-lg leading-relaxed">
          For when public OAuth isn&apos;t set up. Create an Internal Integration at notion.so/my-integrations, paste its secret, and share your database with the integration.
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
