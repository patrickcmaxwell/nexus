import Link from "next/link"
import { getActiveHuman } from "@/lib/auth/session"

export const dynamic = "force-dynamic"

// Public landing page. If the visitor has a valid Nexus session cookie,
// nudges them to the dashboard. Otherwise explains what Arena is and
// points to nexus-web for sign-in.
export default async function HomePage() {
  const me = await getActiveHuman()

  return (
    <main className="min-h-screen flex flex-col">
      {/* Header */}
      <header className="px-8 py-5 flex items-center justify-between border-b border-white/8">
        <div className="flex items-center gap-3">
          <div className="w-2 h-2 rounded-full bg-[var(--arena-accent)] shadow-[0_0_8px_var(--arena-accent)]" />
          <span className="font-mono text-[10px] tracking-[0.3em] uppercase text-[var(--arena-accent)]">
            Arena
          </span>
        </div>
        <div className="flex items-center gap-6">
          {me ? (
            <Link href="/dashboard"
              className="font-mono text-[10px] tracking-[0.2em] uppercase text-white/85 hover:text-white"
            >
              Dashboard →
            </Link>
          ) : (
            <a href={nexusWebUrl()}
              className="font-mono text-[10px] tracking-[0.2em] uppercase text-white/85 hover:text-white"
            >
              Sign in via Nexus →
            </a>
          )}
        </div>
      </header>

      {/* Hero */}
      <div className="flex-1 flex items-center justify-center px-6 py-16">
        <div className="max-w-2xl text-center">
          <p className="font-mono text-[10px] tracking-[0.3em] uppercase text-[var(--arena-accent)] mb-6">
            The executor
          </p>
          <h1 className="text-5xl md:text-6xl font-bold mb-6 leading-[1.05]">
            When Eve says do it,<br />Arena does it.
          </h1>
          <p className="text-lg text-white/65 mb-10 leading-relaxed">
            Connect ClickUp, Stripe, Notion, and the other places work actually happens.
            Eve becomes able to act in the real world — not just talk about it.
          </p>

          {me ? (
            <Link href="/dashboard"
              className="inline-flex items-center gap-2 px-6 py-3 font-mono text-[11px] tracking-[0.25em] uppercase text-[var(--arena-accent)] border border-[var(--arena-accent)]/50 hover:bg-[var(--arena-accent)]/10 transition-colors"
            >
              Open Dashboard
            </Link>
          ) : (
            <a href={nexusWebUrl()}
              className="inline-flex items-center gap-2 px-6 py-3 font-mono text-[11px] tracking-[0.25em] uppercase text-[var(--arena-accent)] border border-[var(--arena-accent)]/50 hover:bg-[var(--arena-accent)]/10 transition-colors"
            >
              Sign in with Nexus
            </a>
          )}
        </div>
      </div>

      {/* Three-up explainer */}
      <section className="px-8 py-16 border-t border-white/8 bg-white/[0.015]">
        <div className="max-w-5xl mx-auto grid grid-cols-1 md:grid-cols-3 gap-10">
          <Block
            title="Connect once"
            body="Drop in API tokens for the services you use. Stored encrypted; never shared between users."
          />
          <Block
            title="Eve takes action"
            body="When you ask Eve to add a task, send a sync, route a payment — Arena routes it to the right service."
          />
          <Block
            title="Audit everything"
            body="Every action Arena takes shows up in your dashboard timeline. Status, latency, what was sent, what came back."
          />
        </div>
      </section>

      <footer className="px-8 py-6 text-center font-mono text-[9px] tracking-[0.25em] uppercase text-white/35">
        Arena · Powered by Nexus
      </footer>
    </main>
  )
}

function Block({ title, body }: { title: string; body: string }) {
  return (
    <div>
      <p className="font-mono text-[10px] tracking-[0.25em] uppercase text-[var(--arena-accent)] mb-2">
        {title}
      </p>
      <p className="text-sm text-white/65 leading-relaxed">{body}</p>
    </div>
  )
}

function nexusWebUrl(): string {
  return process.env.NEXT_PUBLIC_NEXUS_WEB_URL || "https://nexus-web-five-chi.vercel.app"
}
