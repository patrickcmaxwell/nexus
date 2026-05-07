"use client"

import { useState } from "react"
import { useRouter } from "next/navigation"
import { Loader2, CheckCircle2, AlertTriangle, Radio } from "lucide-react"

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

export default function ConnectForm({ provider }: { provider: ProviderInfo }) {
  const router = useRouter()
  const [values, setValues] = useState<Record<string, string>>({})
  const [label, setLabel] = useState("")
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState(false)
  const [testing, setTesting] = useState(false)
  const [testResult, setTestResult] = useState<{ ok: boolean; detail: string } | null>(null)

  async function test() {
    setTesting(true)
    setTestResult(null)
    setError(null)
    try {
      const res = await fetch("/api/connections/test", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ provider: provider.id, values }),
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
      const res = await fetch("/api/connections", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          provider: provider.id,
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

  return (
    <form onSubmit={submit} className="flex flex-col gap-5">
      <Field
        label="Label (optional)"
        helperText={`Names this connection — useful when you have multiple ${provider.name} accounts.`}
        required={false}
      >
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
          helperText={field.helperText}
          required={field.required}
        >
          <input
            type={field.type}
            value={values[field.key] ?? ""}
            onChange={(e) => setValues((v) => ({ ...v, [field.key]: e.target.value }))}
            placeholder={field.placeholder}
            required={field.required}
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
          <p className="text-sm text-emerald-400">Connected — redirecting…</p>
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
          Save Connection
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
      </div>

      <p className="text-[10px] text-white/35 mt-4">
        Credentials live in Supabase, scoped to your account. Eve uses them to act on your behalf via Arena's executor endpoints. Remove the connection from your dashboard at any time.
      </p>
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
