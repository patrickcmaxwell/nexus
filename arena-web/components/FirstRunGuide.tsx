"use client"

// Empty-state onboarding card. Shown when the user has zero connections
// AND zero actions. Clean Apple/Linear style — no HUD chrome.

import Link from "next/link"
import { CheckCircle2, MessageSquare, Plug } from "lucide-react"

type ProviderInfo = {
  id: string
  name: string
  description: string
  accent: string
}

export default function FirstRunGuide({ providers }: { providers: ProviderInfo[] }) {
  const order = ["clickup", "notion", "github", "slack", "stripe"]
  const sorted = [...providers].sort((a, b) => order.indexOf(a.id) - order.indexOf(b.id))
  const starters = sorted.slice(0, 3)

  return (
    <section className="mb-10 rounded-[14px] bg-[color:var(--color-surface)] border border-[color:var(--color-border)] p-7 sm:p-8">
      <h2 className="text-xl font-semibold tracking-tight text-[color:var(--color-fg)] mb-2">
        Three steps to your first action
      </h2>
      <p className="text-base text-[color:var(--color-fg-muted)] leading-relaxed mb-7 max-w-xl">
        Arena turns Eve&apos;s chat instructions into real work in services you already use.
        Connect one, ask Eve to do something, see the receipt land below.
      </p>

      <ol className="grid grid-cols-1 md:grid-cols-3 gap-3 mb-7">
        <Step
          number={1}
          icon={Plug}
          title="Connect a service"
          body="Pick one below and sign in with your account. Eve only sees what you authorize."
        />
        <Step
          number={2}
          icon={MessageSquare}
          title="Ask Eve to do something"
          body={`Open Eve and try "create a task to follow up with Sarah on Friday." She picks the right service automatically.`}
        />
        <Step
          number={3}
          icon={CheckCircle2}
          title="Watch it land"
          body="The action shows up in the activity log below — green check on success, yellow if Eve fell back to mock mode."
        />
      </ol>

      <div>
        <p className="text-sm text-[color:var(--color-fg-muted)] mb-2.5">Recommended starters</p>
        <div className="flex flex-wrap gap-2">
          {starters.map((p) => (
            <Link
              key={p.id}
              href={p.id === "clickup" ? "/connect/clickup" : `/connect/${p.id}`}
              className="px-4 py-2 rounded-lg text-sm font-medium bg-[color:var(--color-surface-2)] border border-[color:var(--color-border)] text-[color:var(--color-fg)] hover:border-[color:var(--color-border-2)] transition-colors"
            >
              Connect {p.name}
            </Link>
          ))}
        </div>
      </div>
    </section>
  )
}

function Step({
  number, icon: Icon, title, body,
}: {
  number: number; icon: typeof CheckCircle2; title: string; body: string
}) {
  return (
    <li className="flex flex-col gap-2.5 p-4 rounded-[14px] bg-[color:var(--color-bg)]/40 border border-[color:var(--color-border)]">
      <div className="flex items-center gap-2.5">
        <span className="w-6 h-6 rounded-full bg-[color:var(--color-accent-soft)] text-[color:var(--color-accent)] text-xs font-semibold flex items-center justify-center">
          {number}
        </span>
        <Icon size={15} className="text-[color:var(--color-fg-muted)]" />
        <p className="text-sm font-medium text-[color:var(--color-fg)]">{title}</p>
      </div>
      <p className="text-sm text-[color:var(--color-fg-muted)] leading-relaxed">{body}</p>
    </li>
  )
}
