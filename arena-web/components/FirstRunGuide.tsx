"use client"

import Link from "next/link"
import { CheckCircle2, MessageSquare, Sparkles, Zap } from "lucide-react"

// FirstRunGuide
//
// Shown on /dashboard when the user has zero connections AND zero actions
// — i.e. they just landed and the empty state would be devastating
// otherwise. Three concrete steps to get from nothing to a real Arena
// action they can see.
//
// Auto-hides as soon as either a connection lands OR an action shows up.

type ProviderInfo = {
  id: string
  name: string
  description: string
  accent: string
}

export default function FirstRunGuide({ providers }: { providers: ProviderInfo[] }) {
  // Sort the recommended starter providers up — the first one a new user
  // sees should be the one most likely to deliver an "aha" moment fast.
  const order = ["clickup", "notion", "github", "slack", "stripe"]
  const sorted = [...providers].sort((a, b) => order.indexOf(a.id) - order.indexOf(b.id))
  const starters = sorted.slice(0, 3)

  return (
    <section
      className="mb-10 p-6 md:p-8"
      style={{
        background:
          "linear-gradient(135deg, color-mix(in oklch, var(--arena-accent) 8%, transparent), color-mix(in oklch, var(--arena-accent) 2%, transparent))",
        border: "1px solid color-mix(in oklch, var(--arena-accent) 30%, transparent)",
      }}
    >
      <div className="flex items-center gap-3 mb-2">
        <Sparkles size={18} style={{ color: "var(--arena-accent)" }} />
        <p
          className="font-mono text-[10px] tracking-[0.3em] uppercase"
          style={{ color: "var(--arena-accent)" }}
        >
          Welcome to Arena
        </p>
      </div>
      <h2 className="text-xl md:text-2xl font-bold mb-2">
        Three steps from now you&apos;ll see Eve do something real.
      </h2>
      <p className="text-sm md:text-base text-white/65 leading-relaxed mb-8 max-w-2xl">
        Arena is the executor — it takes Eve&apos;s tool calls and turns them into action
        in the services you actually use. Connect one, ask Eve to do something, see the
        receipt appear here. It&apos;s that loop.
      </p>

      <ol className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-8">
        <Step
          number={1}
          icon={Zap}
          title="Connect a provider"
          body="Pick one of the integrations below and drop in your API token. Test the connection right in the form so you know it&rsquo;s good before you save."
        />
        <Step
          number={2}
          icon={MessageSquare}
          title="Ask Eve to do something"
          body="Open Eve in nexus-web or Lumen and say something like &ldquo;create a task to follow up with Sarah on Friday.&rdquo; Eve picks the right provider automatically."
        />
        <Step
          number={3}
          icon={CheckCircle2}
          title="Watch it land"
          body="Refresh this page. The action shows up in the log below within seconds, with a green check if it succeeded and a yellow badge if it ran in mock mode."
        />
      </ol>

      {/* Starter provider chips — bigger affordance than the regular grid */}
      <div>
        <p className="font-mono text-[10px] tracking-[0.25em] uppercase text-white/55 mb-3">
          Recommended starters
        </p>
        <div className="flex flex-wrap gap-2">
          {starters.map((p) => (
            <Link
              key={p.id}
              href={`/connect/${p.id}`}
              className="px-4 py-2.5 font-mono text-[11px] tracking-[0.15em] uppercase flex items-center gap-2 transition-all hover:scale-[1.02]"
              style={{
                color: p.accent,
                background: `color-mix(in oklch, ${p.accent} 12%, transparent)`,
                border: `1px solid color-mix(in oklch, ${p.accent} 50%, transparent)`,
              }}
            >
              Connect {p.name}
            </Link>
          ))}
        </div>
      </div>

      <p className="text-xs text-white/35 mt-6">
        Need help? Once you&apos;re past the empty state, this guide disappears. Find it again at{" "}
        <a
          href="https://github.com/patrickcmaxwell/nexus#arena"
          target="_blank"
          rel="noreferrer"
          className="underline"
        >
          the docs
        </a>
        .
      </p>
    </section>
  )
}

function Step({
  number, icon: Icon, title, body,
}: {
  number: number; icon: typeof CheckCircle2; title: string; body: string
}) {
  return (
    <li className="flex flex-col gap-3 p-4 bg-white/[0.025] border border-white/[0.06]">
      <div className="flex items-center gap-3">
        <span
          className="font-mono text-[10px] font-bold tracking-widest text-white/40 px-1.5 py-0.5"
          style={{ border: "1px solid rgba(255,255,255,0.15)" }}
        >
          0{number}
        </span>
        <Icon size={14} style={{ color: "var(--arena-accent)" }} />
        <p className="font-mono text-[10px] tracking-[0.2em] uppercase text-white/85">
          {title}
        </p>
      </div>
      <p className="text-sm text-white/55 leading-relaxed">{body}</p>
    </li>
  )
}
