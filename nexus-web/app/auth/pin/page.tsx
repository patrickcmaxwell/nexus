"use client"

import { useState, useEffect, useCallback } from "react"
import { useRouter } from "next/navigation"

const DIGITS = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"]

// Multi-user PIN sign-in. Identity-first: enter email so the API can pin
// down a single human row by `humans.email`, then verify the PIN hash. The
// owner can also use the legacy passphrase entry at `/` (NexusAuthGate)
// which routes through /api/passphrase and matches the MAXWELL_PIN env var.
//
// Why two entry points: face auth IS identity (biometric → unique human),
// the env-var passphrase is owner-only emergency access, this page is for
// any team member. They all converge on `security_sessions` rows scoped to
// their `humans.id`.
export default function PinPage() {
  const router = useRouter()
  const [email, setEmail] = useState("")
  const [pin, setPin] = useState("")
  const [status, setStatus] = useState<"idle" | "loading" | "error" | "blocked">("idle")
  const [errorMsg, setErrorMsg] = useState("")
  const [shake, setShake] = useState(false)
  const [remember, setRemember] = useState(true)

  // Skip straight to face scan if a verified PIN cookie is present from a
  // recent login on this browser.
  useEffect(() => {
    fetch("/api/security/pin", { method: "GET" })
      .then((r) => { if (r.ok) router.replace("/auth/face") })
      .catch(() => {})
  }, [router])

  // Persist email locally so users don't have to retype on every visit.
  useEffect(() => {
    const stored = localStorage.getItem("nexus.lastEmail")
    if (stored) setEmail(stored)
  }, [])

  const submitPin = useCallback(async (code: string) => {
    if (!email.trim()) {
      setStatus("error")
      setErrorMsg("EMAIL REQUIRED")
      setShake(true)
      setTimeout(() => { setShake(false); setStatus("idle") }, 1500)
      return
    }
    setStatus("loading")
    try {
      const res = await fetch("/api/security/pin", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: email.trim(), pin: code, remember }),
      })
      const data = await res.json()

      if (data.success) {
        localStorage.setItem("nexus.lastEmail", email.trim())
        router.push("/auth/face")
      } else if (data.error === "IP_BLOCKED") {
        setStatus("blocked")
        setErrorMsg("IP BLOCKED — SECURITY LOCKOUT ACTIVE")
      } else {
        setStatus("error")
        setErrorMsg("INVALID CREDENTIALS")
        setShake(true)
        setTimeout(() => setShake(false), 600)
        setPin("")
        setTimeout(() => setStatus("idle"), 2000)
      }
    } catch {
      setStatus("error")
      setErrorMsg("SYSTEM ERROR — RETRY")
      setShake(true)
      setTimeout(() => { setShake(false); setStatus("idle") }, 1500)
      setPin("")
    }
  }, [email, remember, router])

  function handleDigit(d: string) {
    if (status === "loading" || status === "blocked") return
    if (d === "⌫") {
      setPin((p) => p.slice(0, -1))
      return
    }
    if (d === "") return
    const next = pin + d
    setPin(next)
    if (next.length === 4) {
      submitPin(next)
    }
  }

  // Keyboard support — only when the email field isn't focused so users can
  // type "@" and "." without those triggering numpad behavior.
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      const target = e.target as HTMLElement | null
      if (target?.tagName === "INPUT") return
      if (e.key >= "0" && e.key <= "9") handleDigit(e.key)
      if (e.key === "Backspace") handleDigit("⌫")
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [pin, status, email]) // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <div className="min-h-screen bg-background flex items-center justify-center ">
      <div className="w-full max-w-sm px-6">
        <div className="text-center mb-8">
          <div className="w-16 h-16 border border-destructive/40 mx-auto mb-6 flex items-center justify-center">
            <span className="text-destructive font-bold text-2xl animate-pulse-glow">MN</span>
          </div>
          <p className="text-xs text-muted-foreground mb-1">NEXUS // ACCESS</p>
          <h1 className="text-primary text-xl font-bold ">
            SIGN IN
          </h1>
          <p className="text-xs text-muted-foreground mt-2">EMAIL + 4-DIGIT PIN</p>
        </div>

        {/* Email field */}
        <div className="mb-5">
          <label className="block text-xs text-muted-foreground mb-2">EMAIL</label>
          <input
            type="email"
            inputMode="email"
            autoComplete="email"
            autoFocus
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="you@example.com"
            disabled={status === "loading" || status === "blocked"}
            className="w-full px-3 py-2.5 text-sm font-medium border border-border bg-transparent text-primary placeholder:text-muted-foreground/40 focus:outline-none focus:"
          />
        </div>

        {/* PIN dots */}
        <div className={`flex justify-center gap-4 my-6 transition-all ${shake ? "animate-[shake_0.5s_ease-in-out]" : ""}`}>
          {[0, 1, 2, 3].map((i) => (
            <div
              key={i}
              className={`w-4 h-4 rounded-full border-2 transition-all duration-150 ${
                i < pin.length
                  ? status === "error"
                    ? "bg-destructive border-destructive "
                    : "bg-primary border-primary "
                  : "border-border bg-transparent"
              }`}
            />
          ))}
        </div>

        <div className="h-7 mb-5 flex items-center justify-center">
          {status === "loading" && (
            <p className="text-xs font-medium text-primary animate-pulse-glow">VERIFYING...</p>
          )}
          {(status === "error" || status === "blocked") && (
            <p className="text-xs font-medium text-destructive">{errorMsg}</p>
          )}
        </div>

        <div className="grid grid-cols-3 gap-3">
          {DIGITS.map((d, i) => (
            <button
              key={i}
              onClick={() => handleDigit(d)}
              disabled={d === "" || status === "loading" || status === "blocked"}
              className={`
                h-14 text-lg font-semibold transition-all duration-100
                ${d === "" ? "invisible" : ""}
                ${d !== "" && status !== "loading" && status !== "blocked"
                  ? "border border-border text-primary hover:bg-[oklch(0.75_0.18_75/0.1)] hover: active:scale-95"
                  : "opacity-30 cursor-not-allowed border border-border text-muted-foreground"
                }
              `}
             
            >
              {d}
            </button>
          ))}
        </div>

        <button
          onClick={() => setRemember((r) => !r)}
          className="mt-6 w-full flex items-center justify-center gap-3 py-2"
          type="button"
        >
          <div className={`w-4 h-4 border-2 flex items-center justify-center transition-colors ${remember ? "border-primary bg-primary/20" : "border-border"}`}>
            {remember && <span className="text-primary text-[10px] font-bold">✓</span>}
          </div>
          <span className="text-xs text-muted-foreground">
            REMEMBER THIS DEVICE (30 DAYS)
          </span>
        </button>

        <div className="mt-6 text-center">
          <a
            href="/auth/face"
            className="text-xs text-muted-foreground/70 hover:text-primary/80 transition-colors"
          >
            USE FACE INSTEAD →
          </a>
        </div>
      </div>

      <style jsx global>{`
        @keyframes shake {
          0%, 100% { transform: translateX(0); }
          20% { transform: translateX(-8px); }
          40% { transform: translateX(8px); }
          60% { transform: translateX(-6px); }
          80% { transform: translateX(6px); }
        }
      `}</style>
    </div>
  )
}
