"use client"

// /auth/forgot — self-service PIN reset entry point.
//
// User enters their email; the server (when it recognizes them and they're
// not the owner) issues a fresh invite_token, invalidates active sessions,
// and emails the reset link. We always show the same "check your inbox"
// confirmation regardless of whether the email exists, to avoid email
// enumeration.

import { useState } from "react"
import Link from "next/link"
import { Loader2, Mail, ArrowLeft, CheckCircle2, AlertTriangle } from "lucide-react"

export default function ForgotPinPage() {
  const [email, setEmail] = useState("")
  const [stage, setStage] = useState<"idle" | "sending" | "sent" | "error">("idle")
  const [hint, setHint] = useState<string | null>(null)
  const [errorMsg, setErrorMsg] = useState("")

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    if (!email.trim()) return
    setStage("sending")
    setErrorMsg("")
    try {
      const res = await fetch("/api/auth/forgot-pin", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: email.trim() }),
      })
      const data = await res.json().catch(() => ({}))
      if (!res.ok) {
        setStage("error")
        setErrorMsg(data.error || "Unable to start reset")
        return
      }
      setStage("sent")
      if (!data.sent) {
        if (data.reason === "OWNER_NO_SELF_RESET") {
          setHint("This account is the workspace owner — self-reset is disabled. Contact your admin or use the emergency passphrase.")
        } else if (data.reason === "RESEND_API_KEY not configured") {
          setHint("Email isn't configured on this deployment yet. Ask an admin to send you a reset link from the Humans page.")
        } else if (data.reason === "NO_OP") {
          setHint(null) // generic "check inbox" — don't leak existence
        } else {
          setHint(null)
        }
      } else {
        setHint(null)
      }
    } catch {
      setStage("error")
      setErrorMsg("Network error")
    }
  }

  return (
    <div className="min-h-screen bg-background flex items-center justify-center p-6">
      <div className="w-full max-w-sm">
        <div className="text-center mb-8">
          <div className="w-16 h-16 border border-primary/40 mx-auto mb-6 flex items-center justify-center">
            <Mail size={22} className="text-primary" />
          </div>
          <p className="text-xs text-muted-foreground mb-1">NEXUS // RECOVERY</p>
          <h1 className="text-primary text-xl font-bold">Forgot your PIN?</h1>
          <p className="text-xs text-muted-foreground mt-2">
            We&apos;ll email you a link to set a new one.
          </p>
        </div>

        {stage === "sent" ? (
          <div className="flex flex-col gap-4">
            <div className="p-4 rounded-xl bg-emerald-500/10 border border-emerald-500/30 flex items-start gap-3">
              <CheckCircle2 size={18} className="text-emerald-400 mt-0.5 flex-shrink-0" />
              <div>
                <p className="text-sm font-semibold text-emerald-300">Check your inbox</p>
                <p className="text-xs text-emerald-200/70 mt-1">
                  If <span className="font-mono">{email}</span> is on this team, a reset
                  link is on the way. It expires after first use.
                </p>
              </div>
            </div>

            {hint && (
              <div className="p-3 rounded-xl bg-amber-500/10 border border-amber-500/30 flex items-start gap-2">
                <AlertTriangle size={14} className="text-amber-400 mt-0.5 flex-shrink-0" />
                <p className="text-xs text-amber-200/80">{hint}</p>
              </div>
            )}

            <Link
              href="/auth/pin"
              className="self-center text-xs text-muted-foreground hover:text-primary transition-colors flex items-center gap-1.5"
            >
              <ArrowLeft size={12} /> Back to sign in
            </Link>
          </div>
        ) : (
          <form onSubmit={submit} className="flex flex-col gap-4">
            <div>
              <label className="block text-xs text-muted-foreground mb-2">EMAIL</label>
              <input
                type="email"
                inputMode="email"
                autoComplete="email"
                autoFocus
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="you@example.com"
                disabled={stage === "sending"}
                className="w-full px-3 py-2.5 text-sm font-medium border border-border bg-transparent text-primary placeholder:text-muted-foreground/40 focus:outline-none focus:border-primary"
              />
            </div>

            {stage === "error" && (
              <p className="text-xs text-destructive">{errorMsg}</p>
            )}

            <button
              type="submit"
              disabled={stage === "sending" || !email.trim()}
              className="w-full py-2.5 text-sm font-semibold text-primary-foreground bg-primary rounded-lg hover:opacity-90 transition-opacity disabled:opacity-40 flex items-center justify-center gap-2"
            >
              {stage === "sending" ? (
                <><Loader2 size={14} className="animate-spin" /> Sending…</>
              ) : (
                "Send reset link"
              )}
            </button>

            <Link
              href="/auth/pin"
              className="self-center text-xs text-muted-foreground hover:text-primary transition-colors flex items-center gap-1.5"
            >
              <ArrowLeft size={12} /> Back to sign in
            </Link>
          </form>
        )}
      </div>
    </div>
  )
}
