"use client"

import { useState, useEffect, useRef, useCallback } from "react"
import { useRouter, useParams } from "next/navigation"
import { Scan, KeyRound, Loader2, CheckCircle2, Shield, User, Lock } from "lucide-react"

type Stage = "loading" | "invalid" | "used" | "setup_pin" | "setup_face" | "enrolling" | "success"

export default function InvitePage() {
  const router = useRouter()
  const params = useParams()
  const token = params.token as string

  const [stage, setStage] = useState<Stage>("loading")
  const [name, setName] = useState("")
  const [pin, setPin] = useState("")
  const [pinConfirm, setPinConfirm] = useState("")
  const [pinError, setPinError] = useState("")
  const [statusMsg, setStatusMsg] = useState("")

  // Face scan
  const videoRef = useRef<HTMLVideoElement>(null)
  const streamRef = useRef<MediaStream | null>(null)
  const faceapiRef = useRef<any>(null)
  const [faceStatus, setFaceStatus] = useState<"idle" | "loading" | "ready" | "scanning" | "done">("idle")
  const [faceDescriptor, setFaceDescriptor] = useState<number[] | null>(null)

  // Validate the invite token on mount
  useEffect(() => {
    fetch(`/api/team/setup?token=${token}`)
      .then(async (r) => {
        if (r.ok) {
          const data = await r.json()
          setName(data.displayName)
          setStage("setup_pin")
        } else if (r.status === 410) {
          setStage("used")
        } else {
          setStage("invalid")
        }
      })
      .catch(() => setStage("invalid"))
  }, [token])

  function handlePinSubmit(e: React.FormEvent) {
    e.preventDefault()
    setPinError("")
    if (pin.length < 4) {
      setPinError("PIN must be at least 4 digits")
      return
    }
    if (pin !== pinConfirm) {
      setPinError("PINs don't match")
      return
    }
    setStage("setup_face")
  }

  // Start face enrollment
  useEffect(() => {
    if (stage !== "setup_face") return
    startCamera()
  }, [stage])

  async function startCamera() {
    setFaceStatus("loading")
    setStatusMsg("Starting camera...")

    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: "user", width: { ideal: 640 }, height: { ideal: 480 } },
      })
      streamRef.current = stream
      await new Promise((r) => setTimeout(r, 50))
      if (videoRef.current) {
        videoRef.current.srcObject = stream
        videoRef.current.onloadedmetadata = () => videoRef.current?.play().catch(() => {})
      }

      setStatusMsg("Loading face recognition...")
      const faceapi = await import("@vladmandic/face-api")
      const MODEL_URL = "https://cdn.jsdelivr.net/npm/@vladmandic/face-api/model"
      await faceapi.nets.tinyFaceDetector.loadFromUri(MODEL_URL)
      await faceapi.nets.faceLandmark68TinyNet.loadFromUri(MODEL_URL)
      await faceapi.nets.faceRecognitionNet.loadFromUri(MODEL_URL)
      faceapiRef.current = faceapi
      setFaceStatus("ready")
      setStatusMsg("Face the camera and press SCAN to enroll")
    } catch {
      setStatusMsg("Camera unavailable — you can skip face enrollment")
      setFaceStatus("ready") // Still allow skipping
    }
  }

  const runFaceScan = useCallback(async () => {
    if (!faceapiRef.current || !videoRef.current) return
    setFaceStatus("scanning")
    setStatusMsg("Scanning... hold still")

    const faceapi = faceapiRef.current
    const options = new faceapi.TinyFaceDetectorOptions({ inputSize: 320, scoreThreshold: 0.45 })

    let result = null
    for (let i = 0; i < 8; i++) {
      setStatusMsg(`Scanning... attempt ${i + 1} of 8`)
      await new Promise((r) => setTimeout(r, 1000))
      if (!videoRef.current) break
      result = await faceapi.detectSingleFace(videoRef.current, options).withFaceLandmarks(true).withFaceDescriptor()
      if (result) break
    }

    if (result) {
      setFaceDescriptor(Array.from(result.descriptor) as number[])
      setFaceStatus("done")
      setStatusMsg("Face captured successfully!")
    } else {
      setFaceStatus("ready")
      setStatusMsg("No face detected — check lighting and retry")
    }
  }, [])

  async function completeSetup(skipFace = false) {
    setStage("enrolling")
    setStatusMsg("Setting up your account...")

    try {
      const res = await fetch("/api/team/setup", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          token,
          pin,
          faceDescriptor: skipFace ? null : faceDescriptor,
        }),
      })

      if (res.ok) {
        streamRef.current?.getTracks().forEach((t) => t.stop())
        setStage("success")
        setStatusMsg("Welcome to Nexus!")
        setTimeout(() => window.location.replace("/dashboard"), 1500)
      } else {
        const data = await res.json()
        setStage("setup_pin")
        setPinError(data.error || "Setup failed — try again")
      }
    } catch {
      setStage("setup_pin")
      setPinError("Network error — try again")
    }
  }

  // ── Error states ─────────────────────────────────────────────────────────
  if (stage === "loading") {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center">
        <div className="text-center">
          <Loader2 size={24} className="animate-spin mx-auto mb-4" style={{ color: "var(--nexus-cyan)" }} />
          <p className="font-mono text-xs tracking-widest text-muted-foreground uppercase">Verifying invite...</p>
        </div>
      </div>
    )
  }

  if (stage === "invalid") {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center">
        <div className="text-center max-w-sm">
          <Shield size={48} className="mx-auto mb-6 text-destructive" />
          <h1 className="text-xl font-bold text-foreground mb-2">Invalid Invite</h1>
          <p className="text-sm text-muted-foreground">This invite link is invalid or has expired. Contact the Director for a new one.</p>
        </div>
      </div>
    )
  }

  if (stage === "used") {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center">
        <div className="text-center max-w-sm">
          <CheckCircle2 size={48} className="mx-auto mb-6" style={{ color: "var(--nexus-success)" }} />
          <h1 className="text-xl font-bold text-foreground mb-2">Already Activated</h1>
          <p className="text-sm text-muted-foreground mb-6">This invite has already been used. You can log in normally.</p>
          <a href="/" className="font-mono text-xs tracking-widest uppercase" style={{ color: "var(--nexus-cyan)" }}>
            Go to login →
          </a>
        </div>
      </div>
    )
  }

  if (stage === "success") {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center">
        <div className="text-center">
          <CheckCircle2 size={48} className="mx-auto mb-6" style={{ color: "var(--nexus-success)" }} />
          <h1 className="text-2xl font-bold text-foreground mb-2">Welcome, {name}</h1>
          <p className="font-mono text-xs tracking-widest text-muted-foreground uppercase animate-pulse">Entering Nexus...</p>
        </div>
      </div>
    )
  }

  // ── Setup Flow ───────────────────────────────────────────────────────────
  return (
    <div className="min-h-screen bg-background nexus-grid-bg flex flex-col items-center justify-center p-6">
      {/* Glow */}
      <div
        className="absolute inset-0 pointer-events-none"
        style={{ background: "radial-gradient(ellipse 50% 40% at 50% 50%, oklch(0.75 0.18 200 / 0.05) 0%, transparent 70%)" }}
      />

      {/* Header */}
      <div className="relative z-10 mb-8 text-center">
        <p className="font-mono text-[10px] tracking-[0.3em] uppercase mb-1" style={{ color: "var(--nexus-cyan)" }}>
          Nexus
        </p>
        <h1 className="text-2xl font-bold text-foreground mb-1">Welcome, {name}</h1>
        <p className="font-mono text-[9px] tracking-widest text-muted-foreground/60 uppercase">
          {stage === "setup_pin" ? "Step 1 of 2 — Set your PIN" : stage === "enrolling" ? "Finalizing..." : "Step 2 of 2 — Face enrollment"}
        </p>
      </div>

      {/* Card */}
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

        <div className="p-6">
          {/* ── PIN Setup ── */}
          {stage === "setup_pin" && (
            <form onSubmit={handlePinSubmit} className="flex flex-col gap-4">
              <div className="flex items-center gap-3 mb-2">
                <div className="w-10 h-10 rounded-full flex items-center justify-center" style={{ background: "oklch(0.75 0.18 200 / 0.1)", border: "1px solid oklch(0.75 0.18 200 / 0.3)" }}>
                  <Lock size={18} style={{ color: "var(--nexus-cyan)" }} />
                </div>
                <div>
                  <p className="text-sm font-semibold text-foreground">Choose your PIN</p>
                  <p className="text-xs text-muted-foreground">This is your personal access code</p>
                </div>
              </div>

              <div>
                <label className="block font-mono text-[9px] tracking-[0.2em] text-muted-foreground uppercase mb-2">
                  PIN (4+ digits)
                </label>
                <input
                  type="password"
                  inputMode="numeric"
                  pattern="[0-9]*"
                  value={pin}
                  onChange={(e) => setPin(e.target.value.replace(/\D/g, ""))}
                  placeholder="••••"
                  autoFocus
                  maxLength={8}
                  className="w-full px-4 py-3 font-mono text-lg tracking-[0.5em] text-center placeholder:text-muted-foreground/30 focus:outline-none transition-all"
                  style={{
                    background: "oklch(0.08 0.01 240)",
                    border: pinError ? "1px solid var(--nexus-danger)" : "1px solid oklch(0.75 0.18 200 / 0.25)",
                    color: "var(--foreground)",
                  }}
                />
              </div>

              <div>
                <label className="block font-mono text-[9px] tracking-[0.2em] text-muted-foreground uppercase mb-2">
                  Confirm PIN
                </label>
                <input
                  type="password"
                  inputMode="numeric"
                  pattern="[0-9]*"
                  value={pinConfirm}
                  onChange={(e) => setPinConfirm(e.target.value.replace(/\D/g, ""))}
                  placeholder="••••"
                  maxLength={8}
                  className="w-full px-4 py-3 font-mono text-lg tracking-[0.5em] text-center placeholder:text-muted-foreground/30 focus:outline-none transition-all"
                  style={{
                    background: "oklch(0.08 0.01 240)",
                    border: pinError ? "1px solid var(--nexus-danger)" : "1px solid oklch(0.75 0.18 200 / 0.25)",
                    color: "var(--foreground)",
                  }}
                />
              </div>

              {pinError && (
                <p className="font-mono text-[9px] tracking-widest uppercase" style={{ color: "var(--nexus-danger)" }}>
                  {pinError}
                </p>
              )}

              <button
                type="submit"
                disabled={pin.length < 4}
                className="w-full py-3 font-mono text-[10px] tracking-[0.2em] uppercase flex items-center justify-center gap-2 transition-all disabled:opacity-40 disabled:cursor-not-allowed"
                style={{ background: "oklch(0.75 0.18 200 / 0.12)", border: "1px solid oklch(0.75 0.18 200 / 0.5)", color: "var(--nexus-cyan)" }}
              >
                <KeyRound size={13} /> Continue to face enrollment
              </button>
            </form>
          )}

          {/* ── Face Enrollment ── */}
          {stage === "setup_face" && (
            <div className="flex flex-col gap-4">
              <div className="flex items-center gap-3 mb-2">
                <div className="w-10 h-10 rounded-full flex items-center justify-center" style={{ background: "oklch(0.75 0.18 200 / 0.1)", border: "1px solid oklch(0.75 0.18 200 / 0.3)" }}>
                  <Scan size={18} style={{ color: "var(--nexus-cyan)" }} />
                </div>
                <div>
                  <p className="text-sm font-semibold text-foreground">Face enrollment</p>
                  <p className="text-xs text-muted-foreground">Optional — enables biometric login</p>
                </div>
              </div>

              {/* Camera feed */}
              <div className="relative overflow-hidden bg-black" style={{ aspectRatio: "4/3", border: "1px solid oklch(0.75 0.18 200 / 0.2)" }}>
                <div className="absolute top-2 left-2 w-5 h-5 border-t-2 border-l-2 border-[var(--nexus-cyan)]/70 z-10" />
                <div className="absolute top-2 right-2 w-5 h-5 border-t-2 border-r-2 border-[var(--nexus-cyan)]/70 z-10" />
                <div className="absolute bottom-2 left-2 w-5 h-5 border-b-2 border-l-2 border-[var(--nexus-cyan)]/70 z-10" />
                <div className="absolute bottom-2 right-2 w-5 h-5 border-b-2 border-r-2 border-[var(--nexus-cyan)]/70 z-10" />
                <video ref={videoRef} className="w-full h-full object-cover" style={{ transform: "scaleX(-1)" }} muted playsInline autoPlay />

                {faceStatus === "loading" && (
                  <div className="absolute inset-0 bg-black/70 flex flex-col items-center justify-center gap-3 z-20">
                    <Loader2 size={20} className="animate-spin" style={{ color: "var(--nexus-cyan)" }} />
                    <span className="font-mono text-[9px] text-muted-foreground/60 tracking-widest uppercase">{statusMsg}</span>
                  </div>
                )}

                {faceStatus === "done" && (
                  <div className="absolute inset-0 flex items-center justify-center z-20" style={{ background: "oklch(0.65 0.18 155 / 0.15)", border: "2px solid var(--nexus-success)" }}>
                    <CheckCircle2 size={48} style={{ color: "var(--nexus-success)" }} />
                  </div>
                )}
              </div>

              <p className="font-mono text-[10px] tracking-widest text-center uppercase text-muted-foreground">
                {statusMsg}
              </p>

              <div className="flex gap-3">
                {faceStatus === "ready" && (
                  <button
                    type="button"
                    onClick={runFaceScan}
                    className="flex-1 py-2.5 font-mono text-[10px] tracking-[0.2em] uppercase flex items-center justify-center gap-2 transition-all"
                    style={{ background: "oklch(0.75 0.18 200 / 0.12)", border: "1px solid oklch(0.75 0.18 200 / 0.5)", color: "var(--nexus-cyan)" }}
                  >
                    <Scan size={13} /> Scan Face
                  </button>
                )}

                {faceStatus === "scanning" && (
                  <div className="flex-1 py-2.5 font-mono text-[10px] tracking-[0.2em] uppercase border border-border/50 text-muted-foreground flex items-center justify-center gap-2">
                    <Loader2 size={13} className="animate-spin" /> Scanning...
                  </div>
                )}

                {faceStatus === "done" && (
                  <button
                    type="button"
                    onClick={() => completeSetup(false)}
                    className="flex-1 py-2.5 font-mono text-[10px] tracking-[0.2em] uppercase flex items-center justify-center gap-2 transition-all"
                    style={{ background: "oklch(0.65 0.18 155 / 0.12)", border: "1px solid oklch(0.65 0.18 155 / 0.5)", color: "var(--nexus-success)" }}
                  >
                    <CheckCircle2 size={13} /> Complete Setup
                  </button>
                )}
              </div>

              {/* Skip option */}
              {faceStatus !== "scanning" && faceStatus !== "done" && (
                <button
                  type="button"
                  onClick={() => completeSetup(true)}
                  className="w-full py-2 font-mono text-[9px] tracking-[0.15em] uppercase text-muted-foreground/50 hover:text-muted-foreground transition-colors"
                >
                  Skip face enrollment — use PIN only
                </button>
              )}
            </div>
          )}

          {/* ── Enrolling ── */}
          {stage === "enrolling" && (
            <div className="flex flex-col items-center gap-4 py-8">
              <Loader2 size={24} className="animate-spin" style={{ color: "var(--nexus-cyan)" }} />
              <p className="font-mono text-[10px] tracking-widest text-muted-foreground uppercase">{statusMsg}</p>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
