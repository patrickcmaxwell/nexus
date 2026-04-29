"use client"

import { useState, useEffect, useCallback } from "react"
import { useRouter } from "next/navigation"

const DIGITS = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"]

export default function PinPage() {
  const router = useRouter()
  const [pin, setPin] = useState("")
  const [status, setStatus] = useState<"idle" | "loading" | "error" | "blocked">("idle")
  const [errorMsg, setErrorMsg] = useState("")
  const [shake, setShake] = useState(false)
  const [remember, setRemember] = useState(true)

  // If PIN cookie already valid, skip to face scan
  useEffect(() => {
    fetch("/api/security/pin", { method: "GET" })
      .then((r) => { if (r.ok) router.replace("/auth/face") })
      .catch(() => {})
  }, [router])

  const submitPin = useCallback(async (code: string) => {
    setStatus("loading")
    try {
      const res = await fetch("/api/security/pin", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ pin: code, remember }),
      })
      const data = await res.json()

      if (data.success) {
        router.push("/auth/face")
      } else if (data.error === "IP_BLOCKED") {
        setStatus("blocked")
        setErrorMsg("IP BLOCKED — SECURITY LOCKOUT ACTIVE")
      } else {
        setStatus("error")
        setErrorMsg(data.attempts_remaining != null
          ? `INVALID PIN — ${data.attempts_remaining} ATTEMPTS REMAINING`
          : "INVALID PIN")
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
  }, [router])

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

  // Keyboard support
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key >= "0" && e.key <= "9") handleDigit(e.key)
      if (e.key === "Backspace") handleDigit("⌫")
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [pin, status]) // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <div className="min-h-screen bg-background flex items-center justify-center scan-line">
      <div className="w-full max-w-sm px-6">
        {/* Header */}
        <div className="text-center mb-10">
          <div className="w-16 h-16 hud-border hud-glow-red mx-auto mb-6 flex items-center justify-center">
            <span className="text-hud-red font-bold text-2xl animate-pulse-glow" style={{ fontFamily: "var(--font-orbitron)" }}>MN</span>
          </div>
          <p className="font-mono text-[10px] text-muted-foreground tracking-widest mb-1">MAXWELL NEXUS SECURITY</p>
          <h1 className="text-hud-gold text-xl font-bold tracking-widest" style={{ fontFamily: "var(--font-orbitron)" }}>
            DIRECTOR PIN REQUIRED
          </h1>
          <p className="font-mono text-[10px] text-muted-foreground mt-2 tracking-widest">LAYER 1 OF 2 — ENTER 4-DIGIT CODE</p>
        </div>

        {/* PIN dots */}
        <div className={`flex justify-center gap-4 mb-8 transition-all ${shake ? "animate-[shake_0.5s_ease-in-out]" : ""}`}>
          {[0, 1, 2, 3].map((i) => (
            <div
              key={i}
              className={`w-4 h-4 rounded-full border-2 transition-all duration-150 ${
                i < pin.length
                  ? status === "error"
                    ? "bg-hud-red border-hud-red hud-glow-red"
                    : "bg-hud-gold border-hud-gold hud-glow-gold"
                  : "border-border bg-transparent"
              }`}
            />
          ))}
        </div>

        {/* Status message */}
        <div className="h-8 mb-6 flex items-center justify-center">
          {status === "loading" && (
            <p className="font-mono text-[10px] text-hud-gold tracking-widest animate-pulse-glow">VERIFYING...</p>
          )}
          {(status === "error" || status === "blocked") && (
            <p className="font-mono text-[10px] text-hud-red tracking-widest">{errorMsg}</p>
          )}
        </div>

        {/* Numpad */}
        <div className="grid grid-cols-3 gap-3">
          {DIGITS.map((d, i) => (
            <button
              key={i}
              onClick={() => handleDigit(d)}
              disabled={d === "" || status === "loading" || status === "blocked"}
              className={`
                h-14 font-mono text-lg font-bold tracking-widest transition-all duration-100
                ${d === "" ? "invisible" : ""}
                ${d !== "" && status !== "loading" && status !== "blocked"
                  ? "hud-border text-hud-gold hover:bg-[oklch(0.75_0.18_75/0.1)] hover:hud-glow-gold active:scale-95"
                  : "opacity-30 cursor-not-allowed border border-border text-muted-foreground"
                }
              `}
              style={{ fontFamily: "var(--font-orbitron)" }}
            >
              {d}
            </button>
          ))}
        </div>

        {/* Remember device toggle */}
        <button
          onClick={() => setRemember((r) => !r)}
          className="mt-6 w-full flex items-center justify-center gap-3 py-2"
          type="button"
        >
          <div className={`w-4 h-4 border-2 flex items-center justify-center transition-colors ${remember ? "border-hud-gold bg-hud-gold/20" : "border-border"}`}>
            {remember && <span className="text-hud-gold text-[10px] font-bold">✓</span>}
          </div>
          <span className="font-mono text-[10px] text-muted-foreground tracking-widest">
            REMEMBER THIS DEVICE (30 DAYS)
          </span>
        </button>


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
