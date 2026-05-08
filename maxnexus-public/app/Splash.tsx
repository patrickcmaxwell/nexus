"use client"

// Splash — the doorway.
//
// Behavior:
//   1. Ambient particle field on canvas — nodes drift, lines connect nearby
//      pairs, occasional sparks pulse along a connection. Reads as a system
//      thinking quietly.
//   2. Center: a Dagaz rune (ᛞ — Old Norse rune for dawn / awakening / light).
//      Rotates slowly, breathes. Click it.
//   3. Click → a question fades in: "What is light?"
//      Answer "lumen" (case-insensitive) → flash + redirect to portal.
//      Wrong answer → switch to the candle screen.
//   4. Candle screen: a dark candle and one line of text. Click the candle
//      to light it; then click anywhere to try the question again.
//
// Real auth (face / PIN) lives at portal.maxnexus.io. The riddle here is
// flavor + accidental-discovery prevention, not security.

import { useEffect, useRef, useState } from "react"

const PORTAL_URL = process.env.NEXT_PUBLIC_PORTAL_URL || "https://portal.maxnexus.io"
const ANSWER = "lumen"
// Tolerate one typo so a fat-fingered "luman" / "lumin" / "lumens" still opens
// the door. Anything farther than 1 edit away is treated as wrong.
const ANSWER_TOLERANCE = 1

function editDistance(a: string, b: string): number {
  if (a === b) return 0
  if (a.length === 0) return b.length
  if (b.length === 0) return a.length
  const dp: number[] = Array(b.length + 1).fill(0).map((_, i) => i)
  for (let i = 1; i <= a.length; i++) {
    let prev = dp[0]
    dp[0] = i
    for (let j = 1; j <= b.length; j++) {
      const tmp = dp[j]
      dp[j] = a[i - 1] === b[j - 1]
        ? prev
        : 1 + Math.min(prev, dp[j], dp[j - 1])
      prev = tmp
    }
  }
  return dp[b.length]
}

function answerAccepted(input: string): boolean {
  const norm = input.trim().toLowerCase()
  if (!norm) return false
  return editDistance(norm, ANSWER) <= ANSWER_TOLERANCE
}

type Mode = "ambient" | "asking" | "opening" | "candle"

export default function Splash() {
  const [mode, setMode] = useState<Mode>("ambient")
  const [answer, setAnswer] = useState("")
  const [candleLit, setCandleLit] = useState(false)

  function submitAnswer() {
    if (answerAccepted(answer)) {
      setMode("opening")
      // Brief beat of acknowledgement, then go. The flash keeps animating
      // as the page navigates away.
      setTimeout(() => { window.location.href = PORTAL_URL }, 280)
    } else {
      setMode("candle")
      setCandleLit(false)
      setAnswer("")
    }
  }

  function returnToAmbient() {
    setMode("ambient")
    setAnswer("")
    setCandleLit(false)
  }

  return (
    <main className="relative w-full h-dvh overflow-hidden">
      {/* Always-on particle field — backdrop for everything */}
      <ParticleField />

      {/* Mode: ambient → show the rune */}
      {mode === "ambient" && (
        <button
          onClick={() => setMode("asking")}
          aria-label="Speak the word"
          className="absolute inset-0 flex flex-col items-center justify-center z-10 group cursor-pointer"
        >
          <DagazRune />
          <p className="font-mono text-[8px] tracking-[0.5em] text-[var(--muted)] mt-8 select-none opacity-60 group-hover:opacity-100 transition-opacity">
            ASK
          </p>
        </button>
      )}

      {/* Mode: asking → question overlay */}
      {mode === "asking" && (
        <div className="absolute inset-0 flex flex-col items-center justify-center z-20 ask-fade">
          <p className="font-mono text-xs tracking-[0.4em] text-[var(--accent)] uppercase mb-6 opacity-80">
            What is light?
          </p>
          <input
            autoFocus
            type="text"
            value={answer}
            onChange={(e) => setAnswer(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") submitAnswer()
              if (e.key === "Escape") returnToAmbient()
            }}
            className="bg-transparent border-b border-[var(--muted)] text-center font-mono text-base tracking-[0.3em] text-[var(--fg)] focus:outline-none focus:border-[var(--accent)] w-64 py-2 lowercase"
          />
          <p className="font-mono text-[9px] tracking-[0.3em] text-[var(--muted)] mt-6 uppercase opacity-50">
            ENTER · ESC TO RETURN
          </p>
        </div>
      )}

      {/* Mode: opening → bright flash */}
      {mode === "opening" && (
        <div className="absolute inset-0 z-30 pointer-events-none door-open-flash" />
      )}

      {/* Mode: candle → wrong-answer screen */}
      {mode === "candle" && (
        <div
          className="absolute inset-0 flex flex-col items-center justify-center z-20 cursor-pointer"
          onClick={() => {
            if (candleLit) returnToAmbient()
          }}
        >
          <Candle
            lit={candleLit}
            onLight={(e) => {
              e.stopPropagation()
              setCandleLit(true)
            }}
          />
          <p className="font-mono text-xs tracking-[0.3em] text-[var(--muted)] mt-10 uppercase text-center max-w-md px-4 leading-relaxed">
            {!candleLit
              ? "Find a candle and light it."
              : "Now ask again."}
          </p>
        </div>
      )}

      <style>{`
        @keyframes door-open {
          0%   { opacity: 0; }
          40%  { opacity: 0.95; }
          100% { opacity: 0; }
        }
        @keyframes ask-fade {
          0%   { opacity: 0; transform: translateY(8px); }
          100% { opacity: 1; transform: translateY(0); }
        }
        @keyframes spin-rune {
          from { transform: rotate(0deg); }
          to   { transform: rotate(360deg); }
        }
        @keyframes pulse-glow {
          0%, 100% { filter: drop-shadow(0 0 12px rgba(0,200,255,0.25)); opacity: 0.85; }
          50%      { filter: drop-shadow(0 0 28px rgba(0,200,255,0.55)); opacity: 1; }
        }
        @keyframes flame-flicker {
          0%, 100% { transform: scale(1, 1) translateY(0); opacity: 0.95; }
          25%      { transform: scale(0.95, 1.05) translateY(-1px); opacity: 1; }
          50%      { transform: scale(1.05, 0.95) translateY(0); opacity: 0.9; }
          75%      { transform: scale(0.97, 1.03) translateY(-1px); opacity: 1; }
        }
        .door-open-flash {
          background: radial-gradient(ellipse at center, rgba(0,200,255,0.55) 0%, rgba(0,200,255,0) 60%);
          animation: door-open 320ms ease-out forwards;
        }
        .ask-fade {
          animation: ask-fade 400ms ease-out forwards;
        }
        .rune-spin {
          animation: spin-rune 28s linear infinite;
        }
        .rune-glow {
          animation: pulse-glow 5s ease-in-out infinite;
        }
        .flame {
          transform-origin: center bottom;
          animation: flame-flicker 1.2s ease-in-out infinite;
        }
      `}</style>
    </main>
  )
}

// MARK: - Dagaz rune

function DagazRune() {
  // Dagaz: two triangles meeting at center forming an hourglass/bowtie.
  // Means dawn, awakening, breakthrough — the moment light arrives.
  // Wrapped in a slow spin + a separate breathing glow so they animate independently.
  return (
    <div className="rune-glow">
      <div className="rune-spin">
        <svg
          width="56"
          height="56"
          viewBox="-50 -50 100 100"
          aria-hidden
          className="transition-transform duration-300 group-hover:scale-110"
        >
          {/* Outer faint ring */}
          <circle cx="0" cy="0" r="46" fill="none" stroke="var(--accent)" strokeWidth="0.4" opacity="0.18" />
          {/* Dagaz: two triangles meeting at origin */}
          <path
            d="M -34 -28 L 0 0 L -34 28 Z M 34 -28 L 0 0 L 34 28 Z"
            fill="none"
            stroke="var(--accent)"
            strokeWidth="2"
            strokeLinejoin="round"
            opacity="0.85"
          />
          {/* Center mark */}
          <circle cx="0" cy="0" r="1.6" fill="var(--accent)" />
        </svg>
      </div>
    </div>
  )
}

// MARK: - Candle

function Candle({ lit, onLight }: { lit: boolean; onLight: (e: React.MouseEvent) => void }) {
  return (
    <button onClick={onLight} aria-label={lit ? "Candle is lit" : "Light the candle"} className="cursor-pointer">
      <svg width="80" height="160" viewBox="-40 -90 80 170" aria-hidden>
        {/* Flame — only when lit */}
        {lit && (
          <g className="flame">
            {/* Outer warm halo */}
            <ellipse cx="0" cy="-58" rx="22" ry="32" fill="rgba(255,180,80,0.18)" />
            {/* Outer flame */}
            <path
              d="M 0 -82 C -10 -70 -12 -55 -8 -42 C -4 -30 4 -30 8 -42 C 12 -55 10 -70 0 -82 Z"
              fill="rgba(255,180,60,0.85)"
            />
            {/* Inner blue */}
            <path
              d="M 0 -68 C -4 -60 -5 -52 -3 -46 C -1 -40 1 -40 3 -46 C 5 -52 4 -60 0 -68 Z"
              fill="rgba(120,200,255,0.7)"
            />
          </g>
        )}
        {/* Wick */}
        <line x1="0" y1="-40" x2="0" y2="-32" stroke="#1a1a1a" strokeWidth="1.5" strokeLinecap="round" />
        {/* Wax body */}
        <rect x="-14" y="-32" width="28" height="80" rx="2" fill="#e8e1c8" opacity="0.92" />
        {/* Wax highlight */}
        <rect x="-12" y="-30" width="3" height="76" rx="1" fill="#fff8d8" opacity="0.5" />
        {/* Holder */}
        <ellipse cx="0" cy="50" rx="22" ry="6" fill="#3a3530" />
        <rect x="-22" y="48" width="44" height="6" rx="2" fill="#3a3530" />
        {/* Drip */}
        <path d="M -8 30 Q -8 40 -6 42 Q -4 40 -4 30" fill="#e8e1c8" opacity="0.8" />
      </svg>
    </button>
  )
}

// MARK: - Particle field
//
// Canvas-based ambient backdrop. ~50 particles drifting slowly, lines drawn
// between any pair within MAX_LINK_DIST. Occasionally a "spark" fires —
// a brighter pulse that travels along one connection. Reads as a system
// thinking quietly.

function ParticleField() {
  const canvasRef = useRef<HTMLCanvasElement | null>(null)

  useEffect(() => {
    const canvasEl = canvasRef.current
    if (!canvasEl) return
    const ctxOrNull = canvasEl.getContext("2d")
    if (!ctxOrNull) return
    // Local non-nullable refs so nested functions don't have to re-narrow.
    const canvas: HTMLCanvasElement = canvasEl
    const ctx: CanvasRenderingContext2D = ctxOrNull

    let raf = 0
    let width = 0
    let height = 0
    let dpr = window.devicePixelRatio || 1

    type P = { x: number; y: number; vx: number; vy: number; r: number; pulse: number }
    let particles: P[] = []
    type Spark = { fromIdx: number; toIdx: number; t: number; duration: number }
    let sparks: Spark[] = []

    const MAX_LINK_DIST = 140
    const MAX_LINK_DIST_SQ = MAX_LINK_DIST * MAX_LINK_DIST

    function resize() {
      dpr = window.devicePixelRatio || 1
      width = window.innerWidth
      height = window.innerHeight
      canvas.width = width * dpr
      canvas.height = height * dpr
      canvas.style.width = `${width}px`
      canvas.style.height = `${height}px`
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0)

      // Particle count scales with viewport so phones aren't burdened
      const targetCount = Math.min(70, Math.max(28, Math.floor((width * height) / 22000)))
      if (particles.length !== targetCount) {
        particles = Array.from({ length: targetCount }, () => spawn())
      }
    }

    function spawn(): P {
      return {
        x: Math.random() * width,
        y: Math.random() * height,
        vx: (Math.random() - 0.5) * 0.18,
        vy: (Math.random() - 0.5) * 0.18,
        r: 0.8 + Math.random() * 1.4,
        pulse: Math.random() * Math.PI * 2,
      }
    }

    function maybeFireSpark() {
      // Roughly one spark per second. Random connection between two close particles.
      if (Math.random() > 0.018 || sparks.length > 6) return
      const i = Math.floor(Math.random() * particles.length)
      const a = particles[i]
      // Find a partner within range
      const candidates: number[] = []
      for (let j = 0; j < particles.length; j++) {
        if (j === i) continue
        const b = particles[j]
        const dx = a.x - b.x
        const dy = a.y - b.y
        if (dx * dx + dy * dy < MAX_LINK_DIST_SQ) candidates.push(j)
      }
      if (candidates.length === 0) return
      const j = candidates[Math.floor(Math.random() * candidates.length)]
      sparks.push({ fromIdx: i, toIdx: j, t: 0, duration: 600 + Math.random() * 600 })
    }

    let last = performance.now()
    function frame(now: number) {
      const dt = Math.min(50, now - last)
      last = now

      // Update particles
      for (const p of particles) {
        p.x += p.vx * dt
        p.y += p.vy * dt
        p.pulse += dt * 0.0015
        // Wrap around edges so the field never thins out
        if (p.x < -10) p.x = width + 10
        if (p.x > width + 10) p.x = -10
        if (p.y < -10) p.y = height + 10
        if (p.y > height + 10) p.y = -10
      }

      // Update sparks
      sparks = sparks.filter((s) => {
        s.t += dt
        return s.t < s.duration
      })

      maybeFireSpark()

      // Draw — clear with a subtle dark wash for trail effect
      ctx.fillStyle = "rgba(5, 6, 8, 0.92)"
      ctx.fillRect(0, 0, width, height)

      // Connections
      for (let i = 0; i < particles.length; i++) {
        const a = particles[i]
        for (let j = i + 1; j < particles.length; j++) {
          const b = particles[j]
          const dx = a.x - b.x
          const dy = a.y - b.y
          const distSq = dx * dx + dy * dy
          if (distSq > MAX_LINK_DIST_SQ) continue
          const dist = Math.sqrt(distSq)
          // Line opacity falls off with distance
          const alpha = (1 - dist / MAX_LINK_DIST) * 0.18
          ctx.strokeStyle = `rgba(0, 200, 255, ${alpha})`
          ctx.lineWidth = 0.6
          ctx.beginPath()
          ctx.moveTo(a.x, a.y)
          ctx.lineTo(b.x, b.y)
          ctx.stroke()
        }
      }

      // Particles
      for (const p of particles) {
        const breath = 0.7 + Math.sin(p.pulse) * 0.3
        const alpha = 0.4 + breath * 0.45
        ctx.fillStyle = `rgba(180, 230, 255, ${alpha})`
        ctx.beginPath()
        ctx.arc(p.x, p.y, p.r * (0.85 + breath * 0.4), 0, Math.PI * 2)
        ctx.fill()
      }

      // Sparks — bright pulse traveling along the connection
      for (const s of sparks) {
        const a = particles[s.fromIdx]
        const b = particles[s.toIdx]
        if (!a || !b) continue
        const t = s.t / s.duration
        const x = a.x + (b.x - a.x) * t
        const y = a.y + (b.y - a.y) * t
        const fade = 1 - Math.abs(t - 0.5) * 2
        // Bright bead
        ctx.fillStyle = `rgba(180, 240, 255, ${fade})`
        ctx.beginPath()
        ctx.arc(x, y, 2.5, 0, Math.PI * 2)
        ctx.fill()
        // Halo
        ctx.fillStyle = `rgba(0, 200, 255, ${fade * 0.5})`
        ctx.beginPath()
        ctx.arc(x, y, 6, 0, Math.PI * 2)
        ctx.fill()
        // Trail along the segment
        ctx.strokeStyle = `rgba(180, 240, 255, ${fade * 0.6})`
        ctx.lineWidth = 1
        ctx.beginPath()
        ctx.moveTo(a.x, a.y)
        ctx.lineTo(x, y)
        ctx.stroke()
      }

      raf = requestAnimationFrame(frame)
    }

    resize()
    window.addEventListener("resize", resize)
    raf = requestAnimationFrame(frame)

    return () => {
      cancelAnimationFrame(raf)
      window.removeEventListener("resize", resize)
    }
  }, [])

  return (
    <canvas
      ref={canvasRef}
      className="absolute inset-0 z-0 pointer-events-none"
      aria-hidden
    />
  )
}
