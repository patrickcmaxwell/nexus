"use client"

import { useState, useRef, useCallback, useEffect } from "react"
import { Scan, KeyRound, Loader2, CheckCircle2, XCircle, RotateCcw } from "lucide-react"

type FaceStage = "idle" | "loading" | "ready" | "scanning" | "verifying" | "enrolling" | "success" | "failed" | "no_camera"
type Tab = "face" | "passcode"
type Screen = "landing" | "auth"

export default function NexusAuthGate() {
  const [screen, setScreen] = useState<Screen>("landing")
  const [tab, setTab] = useState<Tab>("face")
  const videoRef = useRef<HTMLVideoElement>(null)
  const streamRef = useRef<MediaStream | null>(null)
  const faceapiRef = useRef<any>(null)

  const [faceStage, setFaceStage] = useState<FaceStage>("idle")
  const [loadProgress, setLoadProgress] = useState(0)
  const [statusMsg, setStatusMsg] = useState("")
  const [confidence, setConfidence] = useState(0)

  const [passcode, setPasscode] = useState("")
  const [passStatus, setPassStatus] = useState<"idle" | "checking" | "denied">("idle")

  // Live clock for the HUD
  const [time, setTime] = useState("")
  useEffect(() => {
    const tick = () => setTime(new Date().toLocaleTimeString("en-US", { hour12: false }))
    tick()
    const id = setInterval(tick, 1000)
    return () => clearInterval(id)
  }, [])

  async function startFaceAuth() {
    setScreen("auth")
    setTab("face")
    setFaceStage("loading")
    setStatusMsg("Starting camera...")
    setLoadProgress(0)

    try {
      // Start camera first so the feed is live immediately behind the loading overlay
      let stream: MediaStream
      try {
        stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: "user", width: { ideal: 640 }, height: { ideal: 480 } }
        })
      } catch {
        setFaceStage("no_camera")
        setStatusMsg("Camera unavailable — switching to passcode")
        setTimeout(() => setTab("passcode"), 1200)
        return
      }

      streamRef.current = stream

      // Small tick so React renders the video element before we attach the stream
      await new Promise(r => setTimeout(r, 50))
      if (videoRef.current) {
        videoRef.current.srcObject = stream
        videoRef.current.onloadedmetadata = () => { videoRef.current?.play().catch(() => {}) }
        if (videoRef.current.readyState >= 2) videoRef.current.play().catch(() => {})
      }

      setLoadProgress(20)
      setStatusMsg("Loading biometric engine...")

      const faceapi = await import("@vladmandic/face-api")
      const MODEL_URL = "https://cdn.jsdelivr.net/npm/@vladmandic/face-api/model"
      setLoadProgress(35)
      await faceapi.nets.tinyFaceDetector.loadFromUri(MODEL_URL)
      setLoadProgress(65)
      await faceapi.nets.faceLandmark68TinyNet.loadFromUri(MODEL_URL)
      setLoadProgress(90)
      await faceapi.nets.faceRecognitionNet.loadFromUri(MODEL_URL)
      setLoadProgress(100)
      faceapiRef.current = faceapi

      setFaceStage("ready")
      setStatusMsg("Face the camera and press SCAN")
    } catch (err) {
      setFaceStage("no_camera")
      setStatusMsg("Failed to load biometric engine — use passcode")
      setTab("passcode")
    }
  }

  function openPasscode() {
    setScreen("auth")
    setTab("passcode")
    setFaceStage("idle")
  }

  const runScan = useCallback(async () => {
    if (!faceapiRef.current || !videoRef.current || faceStage !== "ready") return
    setFaceStage("scanning")
    setConfidence(0)
    setStatusMsg("Scanning — hold still...")
    const faceapi = faceapiRef.current
    const options = new faceapi.TinyFaceDetectorOptions({ inputSize: 320, scoreThreshold: 0.45 })
    let result = null
    for (let i = 0; i < 8; i++) {
      setStatusMsg(`Scanning... attempt ${i + 1} of 8`)
      await new Promise(r => setTimeout(r, 1000))
      if (!videoRef.current) break
      result = await faceapi.detectSingleFace(videoRef.current, options).withFaceLandmarks(true).withFaceDescriptor()
      if (result) break
    }
    if (!result) {
      setFaceStage("failed")
      setStatusMsg("No face detected — check lighting and retry")
      return
    }
    setConfidence(Math.round(result.detection.score * 100))
    const descriptor = Array.from(result.descriptor) as number[]
    setFaceStage("verifying")
    setStatusMsg("Verifying identity...")
    const res = await fetch("/api/security/face", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "verify", descriptor }),
    })
    if (res.ok) {
      setFaceStage("success")
      setStatusMsg("Identity confirmed — access granted")
      streamRef.current?.getTracks().forEach(t => t.stop())
      setTimeout(() => { window.location.replace("/dashboard") }, 500)
      return
    }
    if (res.status === 404) {
      setFaceStage("enrolling")
      setStatusMsg("First access — enrolling biometrics...")
      const enrollRes = await fetch("/api/security/face", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "enroll", descriptor }),
      })
      if (enrollRes.ok) {
        setFaceStage("success")
        setStatusMsg("Biometrics enrolled — welcome to Nexus")
        streamRef.current?.getTracks().forEach(t => t.stop())
        setTimeout(() => { window.location.replace("/dashboard") }, 500)
      } else {
        setFaceStage("failed")
        setStatusMsg("Enrollment failed — retry or use passcode")
      }
      return
    }
    setFaceStage("failed")
    setStatusMsg("Identity mismatch — access denied")
  }, [faceStage])

  async function handlePasscode(e: React.FormEvent) {
    e.preventDefault()
    if (!passcode.trim()) return
    setPassStatus("checking")
    try {
      const res = await fetch("/api/passphrase", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ passphrase: passcode }),
        credentials: "include",
      })
      if (res.ok) {
        // Small delay to ensure cookie is set, then redirect
        setTimeout(() => {
          window.location.replace("/dashboard")
        }, 500)
      } else {
        setPassStatus("denied")
        setPasscode("")
        setTimeout(() => setPassStatus("idle"), 2500)
      }
    } catch (err) {
      console.error("[v0] Passphrase error:", err)
      setPassStatus("denied")
      setPasscode("")
      setTimeout(() => setPassStatus("idle"), 2500)
    }
  }

  const isScanning = ["scanning", "verifying", "enrolling"].includes(faceStage)

  // ── LANDING ───────────────────────────────────────────────────────────────
  if (screen === "landing") {
    return (
      <div className="min-h-screen bg-background nexus-grid-bg flex flex-col overflow-hidden">

        {/* Top bar */}
        <header className="flex items-center justify-between px-8 py-4 border-b border-border/50">
          <div className="flex items-center gap-3">
            <div className="w-1.5 h-1.5 rounded-full bg-[var(--nexus-success)] animate-pulse" />
            <span className="font-mono text-[10px] tracking-[0.2em] text-[var(--nexus-cyan)] uppercase">Nexus // System Online</span>
          </div>
          <div className="flex items-center gap-6">
            <span className="font-mono text-[10px] tracking-widest text-muted-foreground">ACCESS_LEVEL: RESTRICTED</span>
            <span className="font-mono text-[10px] tracking-widest text-muted-foreground tabular-nums">{time}</span>
          </div>
        </header>

        {/* Hero */}
        <main className="flex-1 flex flex-col items-center justify-center px-6 relative">

          {/* Radial glow behind the title */}
          <div
            className="absolute inset-0 pointer-events-none"
            style={{
              background: "radial-gradient(ellipse 60% 40% at 50% 50%, oklch(0.75 0.18 200 / 0.06) 0%, transparent 70%)"
            }}
          />

          {/* Decorative corner brackets */}
          <div className="absolute top-8 left-8 w-12 h-12 border-t border-l border-[var(--nexus-cyan)]/30" />
          <div className="absolute top-8 right-8 w-12 h-12 border-t border-r border-[var(--nexus-cyan)]/30" />
          <div className="absolute bottom-8 left-8 w-12 h-12 border-b border-l border-[var(--nexus-cyan)]/30" />
          <div className="absolute bottom-8 right-8 w-12 h-12 border-b border-r border-[var(--nexus-cyan)]/30" />

          <div className="relative z-10 flex flex-col items-center text-center max-w-2xl">

            {/* Status badge */}
            <div className="flex items-center gap-2 mb-8 border border-[var(--nexus-cyan)]/20 bg-[var(--nexus-cyan)]/5 px-4 py-1.5 rounded-sm">
              <div className="w-1.5 h-1.5 rounded-full bg-[var(--nexus-cyan)] animate-pulse" />
              <span className="font-mono text-[10px] tracking-[0.25em] text-[var(--nexus-cyan)] uppercase">
                Secure Command Platform — v1.0
              </span>
            </div>

            {/* Title */}
            <h1
              className="font-mono text-[80px] leading-none font-bold tracking-[0.15em] mb-2"
              style={{
                color: "var(--nexus-cyan)",
                textShadow: "0 0 30px oklch(0.75 0.18 200 / 0.5), 0 0 80px oklch(0.75 0.18 200 / 0.2)",
              }}
            >
              NEXUS
            </h1>

            <p className="font-mono text-[11px] tracking-[0.3em] text-muted-foreground mb-10 uppercase">
              Operational Command Platform
            </p>

            <p className="text-base text-muted-foreground leading-relaxed mb-12 max-w-md font-sans text-pretty">
              A private command center for directing AI agents, managing operations, and planning across all systems — from one place.
            </p>

            {/* Auth buttons */}
            <div className="flex flex-col sm:flex-row gap-4 w-full justify-center">
              <button
                type="button"
                onClick={() => startFaceAuth()}
                className="group relative flex items-center justify-center gap-3 px-8 py-3.5 font-mono text-[11px] tracking-[0.2em] uppercase transition-all"
                style={{
                  background: "oklch(0.75 0.18 200 / 0.1)",
                  border: "1px solid oklch(0.75 0.18 200 / 0.5)",
                  color: "var(--nexus-cyan)",
                }}
                onMouseEnter={e => {
                  (e.currentTarget as HTMLButtonElement).style.background = "oklch(0.75 0.18 200 / 0.18)"
                  ;(e.currentTarget as HTMLButtonElement).style.boxShadow = "0 0 20px oklch(0.75 0.18 200 / 0.2)"
                }}
                onMouseLeave={e => {
                  (e.currentTarget as HTMLButtonElement).style.background = "oklch(0.75 0.18 200 / 0.1)"
                  ;(e.currentTarget as HTMLButtonElement).style.boxShadow = "none"
                }}
              >
                <Scan size={14} />
                Biometric Access
              </button>

              <button
                type="button"
                onClick={() => openPasscode()}
                className="flex items-center justify-center gap-3 px-8 py-3.5 font-mono text-[11px] tracking-[0.2em] uppercase text-muted-foreground border border-border/50 transition-all hover:border-border hover:text-foreground"
              >
                <KeyRound size={14} />
                Passcode Access
              </button>
            </div>

            {/* Warning */}
            <p className="mt-10 font-mono text-[9px] tracking-[0.2em] text-muted-foreground/40 uppercase">
              Unauthorized access is prohibited and monitored
            </p>
          </div>
        </main>

        {/* Bottom bar */}
        <footer className="flex items-center justify-between px-8 py-3 border-t border-border/50">
          <span className="font-mono text-[9px] tracking-widest text-muted-foreground/40 uppercase">End-to-end encrypted</span>
          <span className="font-mono text-[9px] tracking-widest text-muted-foreground/40 uppercase">All sessions logged</span>
        </footer>
      </div>
    )
  }

  // ── AUTH SCREEN ───────────────────────────────────────────────────────────
  return (
    <div className="min-h-screen bg-background nexus-grid-bg flex flex-col items-center justify-center p-6">

      {/* Glow */}
      <div
        className="absolute inset-0 pointer-events-none"
        style={{ background: "radial-gradient(ellipse 50% 40% at 50% 50%, oklch(0.75 0.18 200 / 0.05) 0%, transparent 70%)" }}
      />

      {/* Header */}
      <div className="relative z-10 mb-8 text-center">
        <p className="font-mono text-[10px] tracking-[0.3em] text-[var(--nexus-cyan)] uppercase mb-1">Nexus</p>
        <p className="font-mono text-[9px] tracking-widest text-muted-foreground/60 uppercase">Identity Verification Required</p>
      </div>

      {/* Auth card */}
      <div
        className="relative z-10 w-full max-w-sm overflow-hidden"
        style={{
          background: "oklch(0.10 0.015 240)",
          border: "1px solid oklch(0.75 0.18 200 / 0.25)",
          boxShadow: "0 0 40px oklch(0.75 0.18 200 / 0.08)",
        }}
      >
        {/* Corner accents */}
        <div className="absolute top-0 left-0 w-4 h-4 border-t-2 border-l-2 border-[var(--nexus-cyan)]/60" />
        <div className="absolute top-0 right-0 w-4 h-4 border-t-2 border-r-2 border-[var(--nexus-cyan)]/60" />
        <div className="absolute bottom-0 left-0 w-4 h-4 border-b-2 border-l-2 border-[var(--nexus-cyan)]/60" />
        <div className="absolute bottom-0 right-0 w-4 h-4 border-b-2 border-r-2 border-[var(--nexus-cyan)]/60" />

        {/* Tabs */}
        <div className="flex border-b border-border/50">
          <button
            type="button"
            onClick={() => { setTab("face"); if (faceStage === "idle" || faceStage === "no_camera") startFaceAuth() }}
            className="flex-1 flex items-center justify-center gap-2 py-3.5 font-mono text-[10px] tracking-widest uppercase transition-colors"
            style={{
              color: tab === "face" ? "var(--nexus-cyan)" : "var(--muted-foreground)",
              borderBottom: tab === "face" ? "2px solid var(--nexus-cyan)" : "2px solid transparent",
              marginBottom: "-1px",
            }}
          >
            <Scan size={13} /> Biometric
          </button>
          <button
            type="button"
            onClick={() => {
              streamRef.current?.getTracks().forEach(t => t.stop())
              setTab("passcode")
            }}
            className="flex-1 flex items-center justify-center gap-2 py-3.5 font-mono text-[10px] tracking-widest uppercase transition-colors"
            style={{
              color: tab === "passcode" ? "var(--nexus-cyan)" : "var(--muted-foreground)",
              borderBottom: tab === "passcode" ? "2px solid var(--nexus-cyan)" : "2px solid transparent",
              marginBottom: "-1px",
            }}
          >
            <KeyRound size={13} /> Passcode
          </button>
        </div>

        <div className="p-6">

          {/* ── FACE TAB ── */}
          {tab === "face" && (
            <div className="flex flex-col gap-4">
              {/* Camera viewport */}
              <div className="relative overflow-hidden bg-black" style={{ aspectRatio: "4/3", border: "1px solid oklch(0.75 0.18 200 / 0.2)" }}>
                {/* Corner brackets on the viewport */}
                <div className="absolute top-2 left-2 w-5 h-5 border-t-2 border-l-2 border-[var(--nexus-cyan)]/70 z-10" />
                <div className="absolute top-2 right-2 w-5 h-5 border-t-2 border-r-2 border-[var(--nexus-cyan)]/70 z-10" />
                <div className="absolute bottom-2 left-2 w-5 h-5 border-b-2 border-l-2 border-[var(--nexus-cyan)]/70 z-10" />
                <div className="absolute bottom-2 right-2 w-5 h-5 border-b-2 border-r-2 border-[var(--nexus-cyan)]/70 z-10" />

                {/* Video always in DOM — camera starts live before models load */}
                <video
                  ref={videoRef}
                  className="w-full h-full object-cover"
                  style={{ transform: "scaleX(-1)" }}
                  muted
                  playsInline
                  autoPlay
                />

                {/* Loading overlay — semi-transparent so camera feed shows through */}
                {faceStage === "loading" && loadProgress < 100 && (
                  <div className="absolute inset-0 bg-black/70 flex flex-col items-center justify-center gap-4 z-20">
                    <Loader2 size={22} className="animate-spin" style={{ color: "var(--nexus-cyan)" }} />
                    <div className="w-36">
                      <div className="flex justify-between mb-1">
                        <span className="font-mono text-[8px] text-muted-foreground tracking-widest uppercase">Loading engine</span>
                        <span className="font-mono text-[8px] tabular-nums" style={{ color: "var(--nexus-cyan)" }}>{loadProgress}%</span>
                      </div>
                      <div className="h-0.5 bg-border">
                        <div className="h-full transition-all duration-500" style={{ width: `${loadProgress}%`, background: "var(--nexus-cyan)" }} />
                      </div>
                    </div>
                    <span className="font-mono text-[9px] text-muted-foreground/60 tracking-widest uppercase">{statusMsg}</span>
                  </div>
                )}

                {/* Scan sweep */}
                {isScanning && (
                  <div className="absolute inset-0 overflow-hidden pointer-events-none z-10">
                    <div className="absolute w-full h-12 nexus-scanline" />
                  </div>
                )}

                {/* Success overlay */}
                {faceStage === "success" && (
                  <div className="absolute inset-0 flex items-center justify-center z-20" style={{ background: "oklch(0.65 0.18 155 / 0.15)", border: "2px solid var(--nexus-success)" }}>
                    <CheckCircle2 size={48} style={{ color: "var(--nexus-success)" }} />
                  </div>
                )}

                {/* Failed overlay */}
                {faceStage === "failed" && (
                  <div className="absolute inset-0 flex items-center justify-center z-20" style={{ background: "oklch(0.62 0.22 25 / 0.15)", border: "2px solid var(--nexus-danger)" }}>
                    <XCircle size={48} style={{ color: "var(--nexus-danger)" }} />
                  </div>
                )}

                {/* No camera overlay */}
                {faceStage === "no_camera" && (
                  <div className="absolute inset-0 bg-black/85 flex items-center justify-center z-20">
                    <p className="font-mono text-[10px] text-muted-foreground tracking-widest text-center px-4 uppercase">Camera unavailable</p>
                  </div>
                )}
              </div>

              {/* Confidence bar */}
              {confidence > 0 && (
                <div>
                  <div className="flex justify-between mb-1">
                    <span className="font-mono text-[8px] text-muted-foreground tracking-widest uppercase">Confidence</span>
                    <span className="font-mono text-[8px] tabular-nums" style={{ color: "var(--nexus-cyan)" }}>{confidence}%</span>
                  </div>
                  <div className="h-0.5 bg-border">
                    <div className="h-full transition-all duration-500" style={{ width: `${confidence}%`, background: "var(--nexus-cyan)" }} />
                  </div>
                </div>
              )}

              {/* Status */}
              <p className="font-mono text-[10px] tracking-widest text-center uppercase"
                style={{ color: faceStage === "success" ? "var(--nexus-success)" : faceStage === "failed" ? "var(--nexus-danger)" : "var(--muted-foreground)" }}>
                {statusMsg || "—"}
              </p>

              {/* Actions */}
              {faceStage === "ready" && (
                <button type="button" onClick={runScan}
                  className="w-full py-2.5 font-mono text-[10px] tracking-[0.2em] uppercase flex items-center justify-center gap-2 transition-all"
                  style={{ background: "oklch(0.75 0.18 200 / 0.12)", border: "1px solid oklch(0.75 0.18 200 / 0.5)", color: "var(--nexus-cyan)" }}
                  onMouseEnter={e => { (e.currentTarget as HTMLButtonElement).style.background = "oklch(0.75 0.18 200 / 0.2)" }}
                  onMouseLeave={e => { (e.currentTarget as HTMLButtonElement).style.background = "oklch(0.75 0.18 200 / 0.12)" }}>
                  <Scan size={13} /> Scan
                </button>
              )}
              {faceStage === "failed" && (
                <button type="button" onClick={() => { setFaceStage("ready"); setConfidence(0); setStatusMsg("Face the camera and press SCAN") }}
                  className="w-full py-2.5 font-mono text-[10px] tracking-[0.2em] uppercase border border-border text-muted-foreground hover:text-foreground hover:border-border/80 transition-colors flex items-center justify-center gap-2">
                  <RotateCcw size={13} /> Retry
                </button>
              )}
              {isScanning && (
                <div className="w-full py-2.5 font-mono text-[10px] tracking-[0.2em] uppercase border border-border/50 text-muted-foreground flex items-center justify-center gap-2">
                  <Loader2 size={13} className="animate-spin" /> Processing...
                </div>
              )}
            </div>
          )}

          {/* ── PASSCODE TAB ── */}
          {tab === "passcode" && (
            <form onSubmit={handlePasscode} className="flex flex-col gap-4">
              <div>
                <label className="block font-mono text-[9px] tracking-[0.2em] text-muted-foreground uppercase mb-2">
                  Access Passcode
                </label>
                <input
                  type="password"
                  value={passcode}
                  onChange={e => setPasscode(e.target.value)}
                  placeholder="••••••••"
                  autoComplete="current-password"
                  autoFocus
                  className="w-full px-4 py-3 font-mono text-sm tracking-widest placeholder:text-muted-foreground/30 focus:outline-none transition-all"
                  style={{
                    background: "oklch(0.08 0.01 240)",
                    border: passStatus === "denied" ? "1px solid var(--nexus-danger)" : "1px solid oklch(0.75 0.18 200 / 0.25)",
                    color: "var(--foreground)",
                  }}
                  onFocus={e => { (e.currentTarget as HTMLInputElement).style.borderColor = "oklch(0.75 0.18 200 / 0.6)" }}
                  onBlur={e => { (e.currentTarget as HTMLInputElement).style.borderColor = passStatus === "denied" ? "var(--nexus-danger)" : "oklch(0.75 0.18 200 / 0.25)" }}
                />
                {passStatus === "denied" && (
                  <p className="font-mono text-[9px] tracking-widest uppercase mt-1.5" style={{ color: "var(--nexus-danger)" }}>
                    Access denied — incorrect passcode
                  </p>
                )}
              </div>
              <button
                type="submit"
                disabled={passStatus === "checking" || !passcode.trim()}
                className="w-full py-3 font-mono text-[10px] tracking-[0.2em] uppercase flex items-center justify-center gap-2 transition-all disabled:opacity-40 disabled:cursor-not-allowed"
                style={{ background: "oklch(0.75 0.18 200 / 0.12)", border: "1px solid oklch(0.75 0.18 200 / 0.5)", color: "var(--nexus-cyan)" }}
                onMouseEnter={e => { if (!(e.currentTarget as HTMLButtonElement).disabled) (e.currentTarget as HTMLButtonElement).style.background = "oklch(0.75 0.18 200 / 0.2)" }}
                onMouseLeave={e => { (e.currentTarget as HTMLButtonElement).style.background = "oklch(0.75 0.18 200 / 0.12)" }}
              >
                {passStatus === "checking"
                  ? <><Loader2 size={13} className="animate-spin" /> Verifying...</>
                  : <><KeyRound size={13} /> Unlock Nexus</>}
              </button>
            </form>
          )}
        </div>
      </div>

      <button
        type="button"
        onClick={() => setScreen("landing")}
        className="relative z-10 mt-6 font-mono text-[9px] tracking-[0.2em] uppercase text-muted-foreground/50 hover:text-muted-foreground transition-colors"
      >
        ← Back
      </button>
    </div>
  )
}
