import Link from "next/link"
import { notFound, redirect } from "next/navigation"
import { getActiveHuman } from "@/lib/auth/session"
import { findProvider } from "@/lib/providers"
import ConnectForm from "../../[provider]/ConnectForm"

export const dynamic = "force-dynamic"

export default async function ManualGithubPage() {
  const me = await getActiveHuman()
  if (!me) redirect("/")
  const provider = findProvider("github")
  if (!provider) notFound()

  return (
    <main className="min-h-screen px-4 sm:px-6 py-12 max-w-2xl mx-auto">
      <Link href="/connect/github" className="inline-flex items-center gap-2 text-sm text-[color:var(--color-fg-muted)] hover:text-[color:var(--color-fg)] mb-10">
        ← Back to GitHub
      </Link>

      <header className="mb-10">
        <p className="text-sm text-[color:var(--color-fg-subtle)] mb-2">Manual setup · GitHub</p>
        <h1 className="text-3xl font-semibold tracking-tight">Paste a Personal Access Token</h1>
        <p className="text-base text-[color:var(--color-fg-muted)] mt-3 max-w-lg leading-relaxed">
          For when public OAuth isn&apos;t set up. Generate a token at github.com/settings/tokens → New (classic) → check the <code>repo</code> scope.
        </p>
      </header>

      <ConnectForm provider={{
        id: provider.id, name: provider.name, accent: provider.accent,
        connectFields: provider.connectFields,
      }} />
    </main>
  )
}
