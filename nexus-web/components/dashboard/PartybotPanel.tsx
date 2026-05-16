"use client"

import Link from "next/link"
import { useMemo, useState } from "react"
import { Cpu, Radio, Flame, Wind, Crown, Mountain, Shield, Droplet, AlertCircle, Sparkles, Copy, Check, Activity, CircleDot, XCircle } from "lucide-react"
import { Card, Section, EmptyState, StatTile, Pill, Button } from "@/components/ui/primitives"
import type { PartybotBot, PartybotDevice, PushLogEntry, ActiveDevice } from "@/lib/partybot-supabase/types"

const ARCHETYPE_ICON: Record<string, typeof Flame> = {
  sender: Flame, chill: Wind, host: Crown, shredder: Mountain, guardian: Shield, hydro: Droplet,
}

export default function PartybotPanel({
  configured,
  initialBots,
  initialDevices,
  initialActiveDevices,
  initialRecentPushes,
  fetchError,
}: {
  configured: boolean
  initialBots: PartybotBot[]
  initialDevices: PartybotDevice[]
  initialActiveDevices: ActiveDevice[]
  initialRecentPushes: PushLogEntry[]
  fetchError?: string | null
}) {
  const [bots] = useState<PartybotBot[]>(initialBots)
  const [devices] = useState<PartybotDevice[]>(initialDevices)
  const [activeDevices] = useState<ActiveDevice[]>(initialActiveDevices)
  const [recentPushes] = useState<PushLogEntry[]>(initialRecentPushes)
  const [copied, setCopied] = useState<string | null>(null)

  const canonicalBot = useMemo(() => bots.find((b) => b.is_owner_canonical) ?? bots[0], [bots])
  const botById = useMemo(() => new Map(bots.map((b) => [b.id, b])), [bots])
  const lastSync = useMemo(() => {
    if (activeDevices.length) return activeDevices[0].last_push_at
    const stamps = devices.map((d) => d.last_seen_at).filter((s): s is string => Boolean(s)).sort().reverse()
    return stamps[0] ?? null
  }, [devices])

  async function copyPushCommand(botId: string) {
    const cmd = `cd /Users/shadow/code/ops/v0-partybot5000-concept-discussion && node scripts/push-to-pi.mjs --bot-id ${botId} --host partybot.local`
    try {
      await navigator.clipboard.writeText(cmd)
      setCopied(botId)
      setTimeout(() => setCopied((c) => (c === botId ? null : c)), 1500)
    } catch {
      /* clipboard blocked — leave indicator off */
    }
  }

  return (
    <div className="p-4 md:p-6 space-y-6 max-w-6xl">
      <div className="flex items-center gap-3">
        <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center">
          <Cpu size={20} className="text-primary" />
        </div>
        <div>
          <h1 className="text-2xl font-semibold text-foreground">Partybot</h1>
          <p className="text-sm text-muted-foreground">Bots, devices, and the push helper. Edits land in partybot&rsquo;s Supabase; pushes happen from your laptop.</p>
        </div>
      </div>

      {!configured && (
        <Card tone="warning">
          <div className="flex items-start gap-3">
            <AlertCircle size={18} className="text-warning mt-0.5 flex-shrink-0" />
            <div className="space-y-2 text-sm">
              <p className="font-medium text-foreground">Partybot Supabase not configured.</p>
              <p className="text-muted-foreground">
                Add <code className="px-1 py-0.5 rounded bg-muted text-xs">PARTYBOT_SUPABASE_URL</code> and{" "}
                <code className="px-1 py-0.5 rounded bg-muted text-xs">PARTYBOT_SUPABASE_SERVICE_ROLE_KEY</code> to <code className="px-1 py-0.5 rounded bg-muted text-xs">.env.local</code> (and to Vercel for prod). Until then this cockpit shows empty state.
              </p>
              <p className="text-muted-foreground">
                The Pi runtime + laptop push CLI work independently of this — you can drive the bot from the command line in <code className="px-1 py-0.5 rounded bg-muted text-xs">partybot-pi/README.md</code>.
              </p>
            </div>
          </div>
        </Card>
      )}

      {fetchError && (
        <Card tone="danger">
          <div className="flex items-start gap-3">
            <AlertCircle size={18} className="text-destructive mt-0.5 flex-shrink-0" />
            <div className="text-sm">
              <p className="font-medium text-foreground">Couldn&rsquo;t read partybot data.</p>
              <p className="text-muted-foreground">{fetchError}</p>
            </div>
          </div>
        </Card>
      )}

      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <StatTile label="Bots" value={bots.length} />
        <StatTile label="Canonical" value={canonicalBot?.bot_name ?? "—"} hint={canonicalBot ? canonicalBot.archetype : "set is_owner_canonical"} />
        <StatTile label="Active devices" value={activeDevices.length} hint="distinct Pis pushed to in last 30d" />
        <StatTile label="Last push" value={lastSync ? timeAgo(lastSync) : "never"} hint={lastSync ? new Date(lastSync).toLocaleString() : undefined} />
      </div>

      <Section title="Bots" description={configured ? `${bots.length} in partybot's Supabase` : "Connect partybot's Supabase to populate"}>
        {bots.length === 0 ? (
          <EmptyState
            icon={<Sparkles size={20} />}
            title={configured ? "No bots yet" : "Cockpit standing by"}
            description={configured
              ? "Create one in partybot's bot builder, or push a JSON config directly to your Pi from your laptop."
              : "Once partybot's Supabase is wired, your bots show up here."}
          />
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            {bots.map((b) => {
              const Icon = ARCHETYPE_ICON[b.archetype] ?? Radio
              return (
                <Card key={b.id} padding="md" interactive>
                  <div className="flex items-start gap-3">
                    <Link
                      href={`/dashboard/partybot/${b.id}`}
                      className="w-10 h-10 rounded-lg flex items-center justify-center flex-shrink-0"
                      style={{ background: `${b.color}1a`, color: b.color }}
                      aria-label={`Edit ${b.bot_name}`}
                    >
                      <Icon size={18} />
                    </Link>
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-2 flex-wrap">
                        <Link href={`/dashboard/partybot/${b.id}`} className="font-medium text-foreground truncate hover:text-primary transition-colors">
                          {b.bot_name}
                        </Link>
                        {b.is_owner_canonical && <Pill tone="accent">canonical</Pill>}
                        {b.sass_mode && <Pill tone="warning">sass</Pill>}
                      </div>
                      <p className="text-xs text-muted-foreground mt-0.5">{b.archetype_label}</p>
                      {b.bio && <p className="text-xs text-muted-foreground mt-2 line-clamp-2">{b.bio}</p>}
                      <div className="flex items-center gap-2 mt-3 flex-wrap">
                        <Link href={`/dashboard/partybot/${b.id}`}>
                          <Button size="sm" variant="primary">edit</Button>
                        </Link>
                        <Button
                          size="sm"
                          variant="secondary"
                          onClick={() => copyPushCommand(b.id)}
                          aria-label={`Copy push command for ${b.bot_name}`}
                        >
                          {copied === b.id ? <><Check size={12} /> copied</> : <><Copy size={12} /> push command</>}
                        </Button>
                        <span className="text-[10px] text-muted-foreground">updated {timeAgo(b.updated_at)}</span>
                      </div>
                    </div>
                  </div>
                </Card>
              )
            })}
          </div>
        )}
      </Section>

      <Section title="Active devices" description={configured ? `${activeDevices.length} hosts pushed to in the last 30 days` : "Hosts you push to will appear here"}>
        {activeDevices.length === 0 ? (
          <EmptyState
            icon={<Cpu size={20} />}
            title="No active Pis yet"
            description={configured
              ? "Flash partybot-os.img, drop your owner.pub on the bootfs, boot. The first push from your laptop lights this up."
              : "Push log activates when partybot Supabase is configured."}
          />
        ) : (
          <div className="space-y-2">
            {activeDevices.map((d) => {
              const bot = d.latest_bot_id ? botById.get(d.latest_bot_id) : null
              const statusTone =
                d.last_status === "ok" || d.last_status === "not_modified" ? "success" :
                d.last_status === "error" ? "danger" : "neutral"
              return (
                <Card key={`${d.host}:${d.port}`} padding="sm">
                  <div className="flex items-center justify-between gap-3 flex-wrap">
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-2 flex-wrap">
                        <p className="font-medium text-foreground truncate">{d.host}</p>
                        {d.port !== 8080 && <span className="text-xs text-muted-foreground">:{d.port}</span>}
                        <Pill tone={statusTone} size="xs">{d.last_status}</Pill>
                      </div>
                      {bot && (
                        <p className="text-xs text-muted-foreground mt-0.5">
                          running <span className="text-foreground">{bot.bot_name}</span> · {bot.archetype}
                        </p>
                      )}
                    </div>
                    <div className="text-right text-xs flex-shrink-0">
                      <p className="text-muted-foreground">{d.push_count} push{d.push_count === 1 ? "" : "es"} · {timeAgo(d.last_push_at)}</p>
                      <p className="text-muted-foreground font-mono">{d.last_bundle_hash.slice(0, 12)}…</p>
                    </div>
                  </div>
                </Card>
              )
            })}
          </div>
        )}
      </Section>

      <Section title="Recent pushes" description={configured ? `last ${recentPushes.length} of 200/30d window` : "Push history activates with partybot Supabase"}>
        {recentPushes.length === 0 ? (
          <EmptyState
            icon={<Activity size={20} />}
            title="No pushes logged yet"
            description="Each push from `scripts/push-to-pi.mjs` lands here automatically."
          />
        ) : (
          <Card padding="none" className="overflow-hidden">
            <div className="divide-y divide-border">
              {recentPushes.map((p) => {
                const bot = p.bot_id ? botById.get(p.bot_id) : null
                const statusIcon =
                  p.status === "ok" || p.status === "not_modified" ? <CircleDot size={12} className="text-nexus-success" /> :
                  p.status === "error" ? <XCircle size={12} className="text-destructive" /> :
                  <CircleDot size={12} className="text-muted-foreground" />
                return (
                  <div key={p.id} className="px-3 py-2 flex items-center gap-3 text-xs">
                    <div className="flex-shrink-0">{statusIcon}</div>
                    <div className="min-w-0 flex-1 flex items-baseline gap-2 flex-wrap">
                      <span className="font-medium text-foreground truncate">{bot?.bot_name ?? "—"}</span>
                      <span className="text-muted-foreground truncate">→ {p.host}</span>
                      <span className="font-mono text-muted-foreground">{p.bundle_hash.slice(0, 8)}…</span>
                      {p.error_msg && <span className="text-destructive truncate" title={p.error_msg}>{p.error_msg.slice(0, 40)}</span>}
                    </div>
                    <span className="text-muted-foreground text-[10px] flex-shrink-0" title={new Date(p.pushed_at).toLocaleString()}>
                      {timeAgo(p.pushed_at)}
                    </span>
                  </div>
                )
              })}
            </div>
          </Card>
        )}
      </Section>

      {devices.length > 0 && (
        <Section title="Paired devices (Phase 4)" description="Registered via Pi-side callback (not yet wired)">
          <div className="space-y-2">
            {devices.map((d) => (
              <Card key={d.id} padding="sm">
                <div className="flex items-center justify-between gap-3">
                  <div className="min-w-0">
                    <p className="font-medium text-foreground truncate">{d.label}</p>
                    <p className="text-xs text-muted-foreground font-mono truncate">{d.device_fingerprint.slice(0, 16)}…</p>
                  </div>
                  <div className="text-right text-xs flex-shrink-0">
                    <p className="text-muted-foreground">last seen {d.last_seen_at ? timeAgo(d.last_seen_at) : "never"}</p>
                    {d.last_consciousness_hash && (
                      <p className="text-muted-foreground font-mono">{d.last_consciousness_hash.slice(0, 12)}…</p>
                    )}
                  </div>
                </div>
              </Card>
            ))}
          </div>
        </Section>
      )}
    </div>
  )
}

function timeAgo(iso: string): string {
  const t = new Date(iso).getTime()
  const sec = Math.max(0, Math.floor((Date.now() - t) / 1000))
  if (sec < 60) return `${sec}s ago`
  if (sec < 3600) return `${Math.floor(sec / 60)}m ago`
  if (sec < 86400) return `${Math.floor(sec / 3600)}h ago`
  return `${Math.floor(sec / 86400)}d ago`
}
