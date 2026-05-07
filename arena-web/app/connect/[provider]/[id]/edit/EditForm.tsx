"use client"

import { useState } from "react"
import { useRouter } from "next/navigation"
import { Loader2, CheckCircle2, AlertTriangle, Radio, Trash2, Copy, Webhook } from "lucide-react"

type ConnectionField = {
  key: string
  label: string
  placeholder?: string
  helperText?: string
  required: boolean
  secret: boolean
  type: "text" | "password"
}

type ProviderInfo = {
  id: string
  name: string
  accent: string
  connectFields: ConnectionField[]
}

export default function EditForm({
  connectionId, provider, initialLabel, initialConfig, webhookSecret,
}: {
  connectionId: string
  provider: ProviderInfo
  initialLabel: string
  initialConfig: Record<string, string>
  webhookSecret: string
}) {
  const router = useRouter()
  // Pre-fill non-secret config fields. Secret fields stay blank so the
  // user has to actively re-enter to rotate; blank means "keep existing."
  const [values, setValues] = useState<Record<string, string>>(() => {
    const out: Record<string, string> = {}
    for (const f of provider.connectFields) {
      if (!f.secret) out[f.key] = initialConfig[f.key] ?? ""
    }
    return out
  })
  const [label, setLabel] = useState(initialLabel)
  const [submitting, setSubmitting] = useState(false)
  const [removing, setRemoving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState(false)
  const [testing, setTesting] = useState(false)
  const [testResult, setTestResult] = useState<{ ok: boolean; detail: string } | null>(null)
  const [copied, setCopied] = useState(false)

  const webhookUrl = typeof window === "undefined"
    ? `/api/webhooks/${connectionId}/${webhookSecret}`
    : `${window.location.origin}/api/webhooks/${connectionId}/${webhookSecret}`

  async function copyWebhook() {
    try {
      await navigator.clipboard.writeText(webhookUrl)
      setCopied(true)
      setTimeout(() => setCopied(false), 1500)
    } catch {
      // Clipboard API can fail in non-https contexts; user can copy manually.
    }
  }

  async function test() {
    setTesting(true)
    setTestResult(null)
    setError(null)
    // For test, only include non-empty fields. The endpoint will validate
    // against the provider's required-field list.
    const filtered: Record<string, string> = {}
    for (const [k, v] of Object.entries(values)) if (v !== "") filtered[k] = v
    try {
      const res = await fetch("/api/connections/test", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ provider: provider.id, values: filtered }),
      })
      const data = await res.json().catch(() => ({}))
      setTestResult({ ok: !!data.ok, detail: data.detail || (res.ok ? "" : `HTTP ${res.status}`) })
    } catch (err) {
      setTestResult({ ok: false, detail: err instanceof Error ? err.message : "Network error" })
    } finally {
      setTesting(false)
    }
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    setSubmitting(true)
    setError(null)
    try {
      const res = await fetch(`/api/connections/${connectionId}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          label: label.trim() || null,
          values,
        }),
      })
      const data = await res.json().catch(() => ({}))
      if (!res.ok) {
        setError(data.error || "Failed to save")
        return
      }
      setSuccess(true)
      setTimeout(() => router.push("/dashboard"), 800)
    } catch (err) {
      setError(err instanceof Error ? err.message : "Network error")
    } finally {
      setSubmitting(false)
    }
  }

  async function remove() {
    if (!confirm("Remove this connection? Eve will stop being able to act through this provider.")) return
    setRemoving(true)
    try {
      const res = await fetch(`/api/connections?id=${connectionId}`, { method: "DELETE" })
      if (res.ok) router.push("/dashboard")
    } finally {
      setRemoving(false)
    }
  }

  return (
    <form onSubmit={submit} className="flex flex-col gap-5">
      <Field label="Label (optional)" required={false}>
        <input
          type="text"
          value={label}
          onChange={(e) => setLabel(e.target.value)}
          placeholder={`e.g. "Personal ${provider.name}"`}
          className="w-full px-3 py-2.5 bg-white/[0.04] border border-white/15 focus:border-[color:var(--arena-accent)] focus:outline-none text-white"
          maxLength={80}
        />
      </Field>

      {provider.connectFields.map((field) => (
        <Field
          key={field.key}
          label={field.label}
          helperText={
            field.secret
              ? `${field.helperText ?? ""}${field.helperText ? " " : ""}Leave blank to keep current value.`
              : field.helperText
          }
          required={field.required && !field.secret}  // secret fields aren't required on edit
        >
          <input
            type={field.type}
            value={values[field.key] ?? ""}
            onChange={(e) => setValues((v) => ({ ...v, [field.key]: e.target.value }))}
            placeholder={field.secret ? "•••••••• (unchanged)" : field.placeholder}
            autoComplete={field.secret ? "off" : undefined}
            className="w-full px-3 py-2.5 bg-white/[0.04] border border-white/15 focus:border-[color:var(--arena-accent)] focus:outline-none text-white font-mono"
          />
        </Field>
      ))}

      {error && (
        <div className="flex items-center gap-2 px-3 py-2 bg-red-500/10 border border-red-500/40">
          <AlertTriangle size={14} className="text-red-400" />
          <p className="text-sm text-red-400">{error}</p>
        </div>
      )}

      {success && (
        <div className="flex items-center gap-2 px-3 py-2 bg-emerald-500/10 border border-emerald-500/40">
          <CheckCircle2 size={14} className="text-emerald-400" />
          <p className="text-sm text-emerald-400">Saved — redirecting…</p>
        </div>
      )}

      {testResult && (
        <div className="flex items-center gap-2 px-3 py-2"
          style={{
            background: testResult.ok ? "rgba(52,211,153,0.08)" : "rgba(239,68,68,0.08)",
            border: testResult.ok ? "1px solid rgba(52,211,153,0.4)" : "1px solid rgba(239,68,68,0.4)",
          }}
        >
          {testResult.ok ? (
            <CheckCircle2 size={14} className="text-emerald-400" />
          ) : (
            <AlertTriangle size={14} className="text-red-400" />
          )}
          <p className="text-sm" style={{ color: testResult.ok ? "rgb(52,211,153)" : "rgb(239,68,68)" }}>
            {testResult.detail}
          </p>
        </div>
      )}

      <div className="flex items-center gap-2">
        <button
          type="submit"
          disabled={submitting || success}
          className="px-5 py-2.5 font-mono text-[10px] tracking-[0.25em] uppercase flex items-center gap-2 disabled:opacity-40"
          style={{
            color: provider.accent,
            background: `color-mix(in oklch, ${provider.accent} 12%, transparent)`,
            border: `1px solid color-mix(in oklch, ${provider.accent} 50%, transparent)`,
          }}
        >
          {submitting ? <Loader2 size={12} className="animate-spin" /> : <CheckCircle2 size={12} />}
          Save Changes
        </button>

        <button
          type="button"
          onClick={test}
          disabled={testing || submitting}
          className="px-4 py-2.5 font-mono text-[10px] tracking-[0.25em] uppercase flex items-center gap-2 disabled:opacity-40"
          style={{
            color: "rgba(255,255,255,0.7)",
            background: "rgba(255,255,255,0.04)",
            border: "1px solid rgba(255,255,255,0.18)",
          }}
        >
          {testing ? <Loader2 size={12} className="animate-spin" /> : <Radio size={12} />}
          Test
        </button>

        <button
          type="button"
          onClick={remove}
          disabled={removing}
          className="ml-auto px-4 py-2.5 font-mono text-[10px] tracking-[0.25em] uppercase flex items-center gap-2 disabled:opacity-40"
          style={{
            color: "rgb(239,68,68)",
            background: "rgba(239,68,68,0.08)",
            border: "1px solid rgba(239,68,68,0.4)",
          }}
        >
          {removing ? <Loader2 size={12} className="animate-spin" /> : <Trash2 size={12} />}
          Remove
        </button>
      </div>

      <p className="text-[10px] text-white/35 mt-4">
        Leaving a secret field blank keeps the existing value. Update only what you need to rotate.
      </p>

      <section className="mt-8 pt-6 border-t border-white/10">
        <div className="flex items-center gap-2 mb-2">
          <Webhook size={12} className="text-white/55" />
          <p className="font-mono text-[10px] tracking-[0.25em] uppercase text-white/55">
            Inbound Webhook
          </p>
        </div>
        <p className="text-xs text-white/55 mb-3">
          Paste this URL into {provider.name}&apos;s webhook settings to push events back into Arena.
          Events land in your audit log with an <code className="text-white/75">inbound/</code> prefix.
        </p>
        <div className="flex items-stretch gap-1.5">
          <input
            type="text"
            value={webhookUrl}
            readOnly
            onFocus={(e) => e.currentTarget.select()}
            className="flex-1 px-3 py-2 bg-white/[0.04] border border-white/15 text-white/85 font-mono text-[11px] truncate"
          />
          <button
            type="button"
            onClick={copyWebhook}
            className="px-3 py-2 font-mono text-[10px] tracking-[0.2em] uppercase flex items-center gap-1.5"
            style={{
              color: copied ? "rgb(52,211,153)" : "rgba(255,255,255,0.7)",
              background: "rgba(255,255,255,0.04)",
              border: copied ? "1px solid rgba(52,211,153,0.45)" : "1px solid rgba(255,255,255,0.18)",
            }}
          >
            {copied ? <CheckCircle2 size={11} /> : <Copy size={11} />}
            {copied ? "Copied" : "Copy"}
          </button>
        </div>
        <p className="text-[10px] text-white/35 mt-2">
          The secret in this URL is per-connection. Rotate by removing this connection and adding a new one.
        </p>
      </section>
    </form>
  )
}

function Field({
  label, helperText, required, children,
}: {
  label: string; helperText?: string; required: boolean; children: React.ReactNode
}) {
  return (
    <label className="flex flex-col gap-1.5">
      <span className="font-mono text-[9px] tracking-[0.2em] text-white/55 uppercase">
        {label}{required && <span className="text-red-400 ml-1">*</span>}
      </span>
      {children}
      {helperText && (
        <span className="text-[10px] text-white/40">{helperText}</span>
      )}
    </label>
  )
}
