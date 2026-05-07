import { notFound, redirect } from "next/navigation"
import Link from "next/link"
import { getActiveHuman } from "@/lib/auth/session"
import { getServiceClient } from "@/lib/supabase/service"
import { findProvider } from "@/lib/providers"
import EditForm from "./EditForm"

export const dynamic = "force-dynamic"

export default async function EditConnectionPage({
  params,
}: {
  params: Promise<{ provider: string; id: string }>
}) {
  const me = await getActiveHuman()
  if (!me) redirect("/")
  const { provider: providerId, id } = await params
  const provider = findProvider(providerId)
  if (!provider) notFound()

  const supabase = getServiceClient()
  const { data: connection } = await supabase
    .from("arena_connections")
    .select("id, provider, label, config, status, created_at, updated_at, webhook_secret")
    .eq("id", id)
    .eq("user_id", me.authId)
    .single()
  if (!connection) notFound()

  return (
    <main className="min-h-screen px-6 py-12 max-w-2xl mx-auto">
      <Link href="/dashboard"
        className="font-mono text-[10px] tracking-[0.2em] uppercase text-white/55 hover:text-white inline-block mb-8"
      >
        ← Dashboard
      </Link>

      <header className="mb-10">
        <p className="font-mono text-[10px] tracking-[0.25em] uppercase mb-2"
          style={{ color: provider.accent }}
        >
          Edit · {provider.name}
        </p>
        <h1 className="text-3xl font-bold mb-3">{connection.label || `${provider.name} connection`}</h1>
        <p className="text-sm text-white/65">
          Rotate credentials or update config. Leave the secret fields blank to keep the existing values.
        </p>
      </header>

      <EditForm
        connectionId={connection.id}
        provider={{
          id: provider.id,
          name: provider.name,
          accent: provider.accent,
          connectFields: provider.connectFields,
        }}
        initialLabel={connection.label ?? ""}
        initialConfig={(connection.config as Record<string, string>) ?? {}}
        webhookSecret={connection.webhook_secret as string}
      />
    </main>
  )
}
