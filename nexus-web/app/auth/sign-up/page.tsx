"use client"

import { useState } from "react"
import { createClient } from "@/lib/supabase/client"
import Link from "next/link"

export default function SignUpPage() {
  const [email, setEmail] = useState("")
  const [password, setPassword] = useState("")
  const [confirm, setConfirm] = useState("")
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  async function handleSignUp(e: React.FormEvent) {
    e.preventDefault()
    if (password !== confirm) {
      setError("Access codes do not match.")
      return
    }
    setLoading(true)
    setError(null)
    const supabase = createClient()
    const { error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        emailRedirectTo:
          process.env.NEXT_PUBLIC_DEV_SUPABASE_REDIRECT_URL ??
          `${window.location.origin}/auth/callback`,
      },
    })
    if (error) {
      setError(error.message)
      setLoading(false)
    } else {
      window.location.href = "/auth/sign-up-success"
    }
  }

  return (
    <main className="min-h-screen bg-background flex items-center justify-center scan-line px-4">
      <div className="w-full max-w-md">
        {/* Logo */}
        <div className="flex flex-col items-center gap-3 mb-10">
          <div className="w-16 h-16 hud-border hud-glow-red rounded-sm flex items-center justify-center">
            <span className="text-hud-red font-bold text-2xl animate-pulse-glow" style={{ fontFamily: "var(--font-orbitron)" }}>MX</span>
          </div>
          <h1 className="text-hud-gold text-xl font-bold tracking-widest" style={{ fontFamily: "var(--font-orbitron)" }}>
            MAXWELL NEXUS
          </h1>
          <p className="text-muted-foreground font-mono text-xs tracking-widest">NEW OPERATIVE REGISTRATION</p>
        </div>

        {/* Form */}
        <form onSubmit={handleSignUp} className="hud-border p-8 flex flex-col gap-5 bg-card">
          <div className="border-b border-border pb-4 mb-2">
            <p className="text-hud-gold font-mono text-xs tracking-widest" style={{ fontFamily: "var(--font-orbitron)" }}>
              {">"} REQUEST CLEARANCE
            </p>
          </div>

          <div className="flex flex-col gap-2">
            <label className="font-mono text-xs text-muted-foreground tracking-widest">OPERATOR EMAIL</label>
            <input
              type="email"
              required
              value={email}
              onChange={e => setEmail(e.target.value)}
              className="bg-background hud-border px-4 py-3 font-mono text-sm text-foreground focus:outline-none focus:border-[oklch(0.75_0.18_75)] transition-colors"
              placeholder="operative@maxwell.nexus"
            />
          </div>

          <div className="flex flex-col gap-2">
            <label className="font-mono text-xs text-muted-foreground tracking-widest">ACCESS CODE</label>
            <input
              type="password"
              required
              value={password}
              onChange={e => setPassword(e.target.value)}
              className="bg-background hud-border px-4 py-3 font-mono text-sm text-foreground focus:outline-none focus:border-[oklch(0.75_0.18_75)] transition-colors"
              placeholder="••••••••"
            />
          </div>

          <div className="flex flex-col gap-2">
            <label className="font-mono text-xs text-muted-foreground tracking-widest">CONFIRM ACCESS CODE</label>
            <input
              type="password"
              required
              value={confirm}
              onChange={e => setConfirm(e.target.value)}
              className="bg-background hud-border px-4 py-3 font-mono text-sm text-foreground focus:outline-none focus:border-[oklch(0.75_0.18_75)] transition-colors"
              placeholder="••••••••"
            />
          </div>

          {error && (
            <p className="font-mono text-xs text-hud-red border border-[oklch(0.55_0.22_25/0.4)] px-3 py-2 bg-[oklch(0.55_0.22_25/0.08)]">
              {">"} ERROR: {error}
            </p>
          )}

          <button
            type="submit"
            disabled={loading}
            className="mt-2 px-8 py-3 hud-border-gold hud-glow-gold text-hud-gold font-mono text-sm tracking-widest hover:bg-[oklch(0.75_0.18_75/0.15)] transition-all duration-200 disabled:opacity-50"
            style={{ fontFamily: "var(--font-orbitron)" }}
          >
            {loading ? "REGISTERING..." : "REQUEST ACCESS"}
          </button>

          <p className="text-center font-mono text-xs text-muted-foreground">
            Already cleared?{" "}
            <Link href="/auth/login" className="text-hud-red hover:underline">
              SIGN IN
            </Link>
          </p>
        </form>
      </div>
    </main>
  )
}
