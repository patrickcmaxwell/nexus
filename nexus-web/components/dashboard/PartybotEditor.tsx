"use client"

import Link from "next/link"
import { useState } from "react"
import { useRouter } from "next/navigation"
import { ArrowLeft, Save, Copy, Check, Loader2, AlertCircle, Crown } from "lucide-react"
import { Card, Section, Button, Input, Pill } from "@/components/ui/primitives"
import type { PartybotBot } from "@/lib/partybot-supabase/types"

// Six canonical archetypes — source of truth is partybot's
// components/dashboard/types.ts. Stable list; inlining here avoids a
// cross-repo import for v1.
const ARCHETYPES: { id: string; label: string; tag: string; color: string }[] = [
  { id: "sender",   label: "THE SENDER",    tag: "YOLO.mode",     color: "#00f0ff" },
  { id: "chill",    label: "THE CHILL ONE", tag: "VIBES.only",    color: "#00ff88" },
  { id: "host",     label: "THE HOST",      tag: "HOST.protocol", color: "#ffbd2e" },
  { id: "shredder", label: "THE SHREDDER",  tag: "SEND.IT",       color: "#ff6b35" },
  { id: "guardian", label: "THE GUARDIAN",  tag: "PROTECT.crew",  color: "#bf5af2" },
  { id: "hydro",    label: "THE WATER BOT", tag: "HYDRATE.exe",   color: "#4fc3f7" },
]

// Mirrors lib/consciousness/derive.ts in the partybot repo. Lets the editor
// preview how personality choices change Pi behavior before the push.
function previewMotion(archetype: string, sass: boolean) {
  const base: Record<string, { speed: number; turn: number; react: number }> = {
    sender:   { speed: 0.75, turn: 0.85, react: 22 },
    chill:    { speed: 0.35, turn: 0.30, react: 35 },
    host:     { speed: 0.60, turn: 0.65, react: 28 },
    shredder: { speed: 0.85, turn: 0.90, react: 20 },
    guardian: { speed: 0.50, turn: 0.50, react: 50 },
    hydro:    { speed: 0.45, turn: 0.40, react: 32 },
  }
  const b = base[archetype] ?? base.host
  if (!sass) return b
  return {
    speed: Math.min(1, b.speed * 1.18),
    turn:  Math.min(1, b.turn * 1.15),
    react: Math.max(15, Math.round(b.react * 0.92)),
  }
}

type FormState = {
  bot_name: string
  archetype: string
  sass_mode: boolean
  bio: string
  custom_prompt: string
  rules: string
  friend_rules: string
  is_owner_canonical: boolean
}

function toForm(b: PartybotBot): FormState {
  return {
    bot_name: b.bot_name ?? "",
    archetype: b.archetype ?? "host",
    sass_mode: !!b.sass_mode,
    bio: b.bio ?? "",
    custom_prompt: b.custom_prompt ?? "",
    rules: b.rules ?? "",
    friend_rules: b.friend_rules ?? "",
    is_owner_canonical: !!b.is_owner_canonical,
  }
}

export default function PartybotEditor({ initialBot }: { initialBot: PartybotBot }) {
  const router = useRouter()
  const [form, setForm] = useState<FormState>(toForm(initialBot))
  const [original] = useState<FormState>(toForm(initialBot))
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [copied, setCopied] = useState(false)

  const dirty = JSON.stringify(form) !== JSON.stringify(original)
  const motion = previewMotion(form.archetype, form.sass_mode)
  const archetypeMeta = ARCHETYPES.find((a) => a.id === form.archetype) ?? ARCHETYPES[2]

  function set<K extends keyof FormState>(k: K, v: FormState[K]) {
    setForm((f) => ({ ...f, [k]: v }))
  }

  async function save() {
    if (!dirty || saving) return
    setSaving(true)
    setError(null)
    try {
      const res = await fetch(`/api/partybot/bot/${initialBot.id}`, {
        method: "PATCH",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          ...form,
          archetype_label: archetypeMeta.label,
          tag: archetypeMeta.tag,
          color: archetypeMeta.color,
        }),
        credentials: "include",
      })
      if (!res.ok) {
        const msg = await res.text()
        throw new Error(msg || `${res.status}`)
      }
      router.refresh()
    } catch (e: any) {
      setError(e?.message ?? "save failed")
    } finally {
      setSaving(false)
    }
  }

  async function copyPushCommand() {
    const cmd = `cd /Users/shadow/code/ops/v0-partybot5000-concept-discussion && node scripts/push-to-pi.mjs --bot-id ${initialBot.id} --host partybot.local`
    try {
      await navigator.clipboard.writeText(cmd)
      setCopied(true)
      setTimeout(() => setCopied(false), 1500)
    } catch {
      /* clipboard blocked */
    }
  }

  return (
    <div className="p-4 md:p-6 space-y-6 max-w-5xl">
      <div className="flex items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <Link
            href="/dashboard/partybot"
            className="w-9 h-9 rounded-lg bg-secondary hover:bg-muted flex items-center justify-center text-muted-foreground hover:text-foreground transition-colors"
          >
            <ArrowLeft size={16} />
          </Link>
          <div>
            <h1 className="text-2xl font-semibold text-foreground">{form.bot_name || "Untitled"}</h1>
            <p className="text-sm text-muted-foreground">{archetypeMeta.label} · {form.sass_mode ? "sass on" : "sass off"}</p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <Button variant="secondary" size="sm" onClick={copyPushCommand} aria-label="Copy push command">
            {copied ? <><Check size={14} /> copied</> : <><Copy size={14} /> push command</>}
          </Button>
          <Button variant="primary" size="sm" onClick={save} loading={saving} disabled={!dirty || saving}>
            <Save size={14} /> {dirty ? "save" : "saved"}
          </Button>
        </div>
      </div>

      {error && (
        <Card tone="danger">
          <div className="flex items-start gap-3 text-sm">
            <AlertCircle size={16} className="text-destructive mt-0.5 flex-shrink-0" />
            <div><p className="font-medium text-foreground">save failed</p><p className="text-muted-foreground">{error}</p></div>
          </div>
        </Card>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        {/* ── left column: identity + behavior text ─────────────────────────── */}
        <div className="lg:col-span-2 space-y-4">
          <Section title="Identity">
            <Card padding="md" className="space-y-3">
              <Field label="Name">
                <Input value={form.bot_name} onChange={(e) => set("bot_name", e.target.value)} placeholder="PARTYBOT_5000" />
              </Field>
              <Field label="Bio" hint="one-liner that shows on the bot card">
                <Input value={form.bio} onChange={(e) => set("bio", e.target.value)} placeholder="patrick's house bot. cyan-and-amber soul." />
              </Field>
            </Card>
          </Section>

          <Section title="Soul" description="custom_prompt + rules drive how the bot thinks and what it won't do">
            <Card padding="md" className="space-y-3">
              <Field label="Custom prompt" hint="what the bot is, in its own voice">
                <TextArea value={form.custom_prompt} onChange={(v) => set("custom_prompt", v)} rows={5} />
              </Field>
              <Field label="Rules" hint="what the bot should not do">
                <TextArea value={form.rules} onChange={(v) => set("rules", v)} rows={4} />
              </Field>
              <Field label="Friend rules" hint="how the bot treats other bots">
                <TextArea value={form.friend_rules} onChange={(v) => set("friend_rules", v)} rows={3} />
              </Field>
            </Card>
          </Section>
        </div>

        {/* ── right column: archetype + flags + motion preview ──────────────── */}
        <div className="space-y-4">
          <Section title="Archetype">
            <div className="grid grid-cols-2 gap-2">
              {ARCHETYPES.map((a) => {
                const active = a.id === form.archetype
                return (
                  <button
                    key={a.id}
                    type="button"
                    onClick={() => set("archetype", a.id)}
                    className={`p-3 rounded-lg border text-left transition-all ${
                      active ? "border-primary bg-primary/5" : "border-border hover:border-primary/40 hover:bg-primary/3"
                    }`}
                  >
                    <div className="w-6 h-6 rounded mb-2" style={{ background: `${a.color}33`, border: `1px solid ${a.color}` }} />
                    <p className="text-xs font-semibold text-foreground">{a.label}</p>
                    <p className="text-[10px] text-muted-foreground mt-0.5">{a.tag}</p>
                  </button>
                )
              })}
            </div>
          </Section>

          <Section title="Flags">
            <Card padding="md" className="space-y-3">
              <Toggle
                checked={form.sass_mode}
                onChange={(v) => set("sass_mode", v)}
                label="sass mode"
                hint="amps speed + turn aggression + quip frequency"
              />
              <Toggle
                checked={form.is_owner_canonical}
                onChange={(v) => set("is_owner_canonical", v)}
                label="canonical for devices"
                hint="this is the bot your Pi pulls from when pushed by id"
              />
              {form.is_owner_canonical && (
                <div className="flex items-center gap-2 text-xs text-warning">
                  <Crown size={12} /> exactly one canonical bot per user — saving here may flip others off
                </div>
              )}
            </Card>
          </Section>

          <Section title="Motion preview" description="how this personality moves on the Pi">
            <Card padding="md">
              <dl className="text-xs space-y-1.5">
                <Row label="base speed"  value={`${(motion.speed * 100).toFixed(0)}%`} />
                <Row label="turn aggression" value={`${(motion.turn * 100).toFixed(0)}%`} />
                <Row label="react radius"  value={`${motion.react} cm`} />
              </dl>
            </Card>
          </Section>
        </div>
      </div>

      <p className="text-xs text-muted-foreground">
        Save updates partybot&rsquo;s Supabase. Pushing to the Pi still happens from your laptop with your local owner key — click <Pill tone="accent" size="xs">push command</Pill> above, paste into your terminal.
      </p>
    </div>
  )
}

// ─── small helpers ───────────────────────────────────────────────────────

function Field({ label, hint, children }: { label: string; hint?: string; children: React.ReactNode }) {
  return (
    <div>
      <div className="flex items-baseline justify-between mb-1.5">
        <label className="text-xs font-medium text-foreground">{label}</label>
        {hint && <span className="text-[10px] text-muted-foreground">{hint}</span>}
      </div>
      {children}
    </div>
  )
}

function TextArea({ value, onChange, rows = 4 }: { value: string; onChange: (v: string) => void; rows?: number }) {
  return (
    <textarea
      value={value}
      onChange={(e) => onChange(e.target.value)}
      rows={rows}
      className="w-full px-3 py-2 rounded-lg bg-secondary border border-border text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/40 focus:border-primary/40 resize-y"
    />
  )
}

function Toggle({ checked, onChange, label, hint }: { checked: boolean; onChange: (v: boolean) => void; label: string; hint?: string }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      onClick={() => onChange(!checked)}
      className="w-full flex items-center justify-between gap-3 text-left group"
    >
      <div>
        <p className="text-xs font-medium text-foreground">{label}</p>
        {hint && <p className="text-[10px] text-muted-foreground mt-0.5">{hint}</p>}
      </div>
      <div className={`w-9 h-5 rounded-full flex-shrink-0 transition-colors ${checked ? "bg-primary" : "bg-muted"}`}>
        <div className={`w-4 h-4 rounded-full bg-background mt-0.5 transition-transform ${checked ? "translate-x-[18px]" : "translate-x-0.5"}`} />
      </div>
    </button>
  )
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-baseline justify-between">
      <dt className="text-muted-foreground">{label}</dt>
      <dd className="font-mono text-foreground">{value}</dd>
    </div>
  )
}
