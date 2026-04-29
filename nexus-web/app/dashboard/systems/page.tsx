"use client"

import { useEffect, useState } from "react"

const SUBSYSTEMS = [
  { name: "REPULSOR ARRAY", base: 94 },
  { name: "STEALTH MODULE", base: 87 },
  { name: "AI CORE", base: 98 },
  { name: "NANO REPAIR", base: 91 },
  { name: "WEAPONS GRID", base: 89 },
  { name: "COMMS ARRAY", base: 96 },
  { name: "POWER GRID", base: 100 },
  { name: "TARGETING SYS", base: 93 },
]

const ALERTS = [
  { time: "04:12:33", type: "INFO", msg: "Arc reactor output optimized — 100% efficiency" },
  { time: "03:55:17", type: "WARN", msg: "Stealth module calibration drift detected — auto-correcting" },
  { time: "03:41:02", type: "INFO", msg: "Nano-repair sequence completed on Mark L gauntlet" },
  { time: "02:28:50", type: "CRIT", msg: "Threat signal detected — Sector 7 — resolved" },
  { time: "01:14:09", type: "INFO", msg: "All backup power cells fully charged" },
]

function jitter(base: number) {
  return Math.max(60, Math.min(100, base + Math.floor(Math.random() * 7) - 3))
}

export default function SystemsPage() {
  const [values, setValues] = useState(SUBSYSTEMS.map((s) => s.base))

  useEffect(() => {
    const interval = setInterval(() => {
      setValues(SUBSYSTEMS.map((s) => jitter(s.base)))
    }, 1800)
    return () => clearInterval(interval)
  }, [])

  function barColor(v: number) {
    if (v >= 90) return "bg-green-400"
    if (v >= 70) return "bg-yellow-400"
    return "bg-hud-red"
  }

  function labelColor(v: number) {
    if (v >= 90) return "text-green-400"
    if (v >= 70) return "text-yellow-400"
    return "text-hud-red"
  }

  const alertColor: Record<string, string> = {
    INFO: "text-hud-gold",
    WARN: "text-yellow-400",
    CRIT: "text-hud-red",
  }

  const arcPower = values[6]

  return (
    <div className="p-8 scan-line min-h-screen">
      <div className="mb-8">
        <p className="font-mono text-xs text-muted-foreground mb-1" style={{ fontFamily: "var(--font-orbitron)" }}>{">"} ENGINEERING</p>
        <h1 className="text-2xl font-bold text-hud-gold tracking-widest" style={{ fontFamily: "var(--font-orbitron)" }}>SYSTEM DIAGNOSTICS</h1>
      </div>

      <div className="grid lg:grid-cols-3 gap-6 mb-6">
        {/* Arc Reactor */}
        <div className="hud-border bg-card p-6 flex flex-col items-center justify-center">
          <p className="font-mono text-[10px] text-muted-foreground mb-4 tracking-widest" style={{ fontFamily: "var(--font-orbitron)" }}>ARC REACTOR</p>
          <div className="relative flex items-center justify-center mb-4">
            {[56, 44, 32, 20].map((size) => (
              <div key={size} className="absolute rounded-full border border-[oklch(0.75_0.18_75/0.2)] animate-pulse-glow" style={{ width: size * 2, height: size * 2 }} />
            ))}
            <div className="w-12 h-12 rounded-full bg-[oklch(0.75_0.18_75/0.15)] hud-border-gold hud-glow-gold flex items-center justify-center z-10">
              <span className="font-mono text-sm font-bold text-hud-gold" style={{ fontFamily: "var(--font-orbitron)" }}>{arcPower}</span>
            </div>
          </div>
          <p className={`font-mono text-xs font-bold ${labelColor(arcPower)}`} style={{ fontFamily: "var(--font-orbitron)" }}>
            {arcPower >= 90 ? "NOMINAL" : arcPower >= 70 ? "DEGRADED" : "CRITICAL"}
          </p>
        </div>

        {/* Subsystems */}
        <div className="lg:col-span-2 hud-border bg-card p-6">
          <p className="font-mono text-[10px] text-hud-gold tracking-widest mb-5" style={{ fontFamily: "var(--font-orbitron)" }}>SUBSYSTEM STATUS</p>
          <div className="grid grid-cols-2 gap-x-8 gap-y-3">
            {SUBSYSTEMS.map((s, i) => (
              <div key={s.name}>
                <div className="flex items-center justify-between mb-1">
                  <span className="font-mono text-[10px] text-muted-foreground" style={{ fontFamily: "var(--font-orbitron)" }}>{s.name}</span>
                  <span className={`font-mono text-[10px] ${labelColor(values[i])}`}>{values[i]}%</span>
                </div>
                <div className="h-1.5 bg-muted rounded-sm overflow-hidden">
                  <div className={`h-full rounded-sm transition-all duration-700 ${barColor(values[i])}`} style={{ width: `${values[i]}%` }} />
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Event Log */}
      <div className="hud-border bg-card p-6">
        <p className="font-mono text-[10px] text-hud-gold tracking-widest mb-4" style={{ fontFamily: "var(--font-orbitron)" }}>SYSTEM EVENT LOG</p>
        <div className="flex flex-col gap-2">
          {ALERTS.map((a, i) => (
            <div key={i} className="flex items-start gap-4 border-b border-border pb-2 last:border-0 last:pb-0">
              <span className="font-mono text-[10px] text-muted-foreground w-16 flex-shrink-0">{a.time}</span>
              <span className={`font-mono text-[10px] w-10 flex-shrink-0 ${alertColor[a.type]}`} style={{ fontFamily: "var(--font-orbitron)" }}>{a.type}</span>
              <span className="font-mono text-[10px] text-muted-foreground">{a.msg}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
