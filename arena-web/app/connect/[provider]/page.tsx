import { notFound, redirect } from "next/navigation"
import { getActiveHuman } from "@/lib/auth/session"
import { findProvider } from "@/lib/providers"
import ConnectForm from "./ConnectForm"

export const dynamic = "force-dynamic"

export default async function ConnectPage({ params }: { params: Promise<{ provider: string }> }) {
  const me = await getActiveHuman()
  if (!me) redirect("/")
  const { provider: providerId } = await params
  const provider = findProvider(providerId)
  if (!provider) notFound()

  return (
    <main className="min-h-screen px-6 py-12 max-w-2xl mx-auto">
      <a href="/dashboard"
        className="font-mono text-[10px] tracking-[0.2em] uppercase text-white/55 hover:text-white inline-block mb-8"
      >
        ← Dashboard
      </a>

      <header className="mb-10">
        <p className="font-mono text-[10px] tracking-[0.25em] uppercase mb-2"
          style={{ color: provider.accent }}
        >
          Connect · {provider.name}
        </p>
        <h1 className="text-3xl font-bold mb-3">{provider.name}</h1>
        <p className="text-sm text-white/65">{provider.description}</p>
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
