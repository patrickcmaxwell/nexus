"use client"

import { useEffect, useRef, useState, useCallback } from "react"
import { Scan, KeyRound, Loader2, CheckCircle2, XCircle } from "lucide-react"

type Stage = "loading" | "ready" | "scanning" | "verifying" | "enrolling" | "success" | "failed" | "no_camera"
type Tab = "face" | "passcode"

export default function ReAuthGate({ children }: { children: React.ReactNode }) {
  const [verified, setVerified] = useState(false)
  const [mounted, setMounted] = useState(false)

  useEffect(() => {
    setMounted(true)
    if (sessionStorage.getItem("nx_verified") === "1") setVerified(true)
  }, [])

  function onVerified() {
    sessionStorage.setItem("nx_verified", "1")
    setVerified(true)
  }

  if (!mounted) return null
  if (verified) return <>{children}</>
  return <AuthOverlay onVerified={onVerified} />
}

function AuthOverlay({ onVerified }: { onVerified: () => void }) {
  const [tab, setTab] = useState<Tab>("face")
  const [stage, setStage] = useState<Stage>("loading")
  const [loadProgress, setLoadProgress] = useState(0)
  const [statusMsg, setStatusMsg] = useState("Initialising biometric engine...")
  const [confidence, setConfidence] = useState(0)
  const [passcode, setPasscode] = useState("")
  const [passStatus, setPassStatus] = useState<"idle" | "checking" | "denied">("idle")
  const [time, setTime] = useState("")

  // The video element is always in the DOM — never conditionally rendered
  const videoRef = useRef<HTMLVideoElement>(null)
  const streamRef = useRef<MediaStream | null>(null)
  const faceapiRef = useRef<any>(null)
  const modelsLoadedRef = useRef(false)

  // Live clock
  useEffect(() => {
    const tick = () => setTime(new Date().toLocaleTimeString("en-US", { hour12: false }))
    tick()
    const id = setInterval(tick, 1000)
    return () => clearInterval(id)
  }, [])

  // Key fix: whenever stream changes, attach it to the video element
  useEffect(() => {
    const video = videoRef.current
    if (!video || !streamRef.current) return
    video.srcObject = streamRef.current
    video.muted = true
    video.playsInline = true
    video.play().catch(() => {
      // Some browsers need a user gesture — the video will still display
    })
  }, [stage]) // re-run when stage changes so it retries after DOM updates

  // Auto-start on mount
  useEffect(() => {
    initFaceAuth()
    return () => {
      streamRef.current?.getTracks().forEach(t => t.stop())
    }
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  async function initFaceAuth() {
    setStage("loading")
    setLoadProgress(0)
    setStatusMsg("Requesting camera access...")

    // Step 1: Start camera FIRST so the user sees themselves immediately
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: "user", width: { ideal: 640 }, height: { ideal: 480 } },
        audio: false,
      })
      streamRef.current = stream

      // Attach to video — the useEffect above will fire when stage changes,
      // but also attach directly here as the primary path
      const video = videoRef.current
      if (video) {
        video.srcObject = stream
        video.muted = true
        video.playsInline = true
        video.play().catch(() => {})
      }
    } catch {
      setStage("no_camera")
      setStatusMsg("Camera unavailable — use passcode")
      setTab("passcode")
      return
    }

    // Step 2: Load face-api models (camera is already live in the background)
    setLoadProgress(15)
    setStatusMsg("Camera live — loading biometric models...")

    try {
      if (!modelsLoadedRef.current) {
        const faceapi = await import("@vladmandic/face-api")
        const MODEL_URL = "https://cdn.jsdelivr.net/npm/@vladmandic/face-api/model"
        setLoadProgress(30)
        await faceapi.nets.tinyFaceDetector.loadFromUri(MODEL_URL)
        setLoadProgress(60)
        await faceapi.nets.faceLandmark68TinyNet.loadFromUri(MODEL_URL)
        setLoadProgress(85)
        await faceapi.nets.faceRecognitionNet.loadFromUri(MODEL_URL)
        setLoadProgress(100)
        faceapiRef.current = faceapi
        modelsLoadedRef.current = true
      }

      setStage("ready")
      setStatusMsg("Face the camera — press SCAN to identify")
    } catch {
      setStage("no_camera")
      setStatusMsg("Biometric engine failed — use passcode")
      setTab("passcode")
    }
  }

  const runScan = useCallback(async () => {
    if (!faceapiRef.current || !videoRef.current || stage !== "ready") return
    setStage("scanning")
    setConfidence(0)
    setStatusMsg("Scanning — hold still...")

    const faceapi = faceapiRef.current
    const options = new faceapi.TinyFaceDetectorOptions({ inputSize: 320, scoreThreshold: 0.45 })

    let result = null
    for (let i = 0; i < 8; i++) {
      setStatusMsg(`Scanning... attempt ${i + 1} of 8`)
      await new Promise(r => setTimeout(r, 900))
      if (!videoRef.current) break
      // Make sure stream is still attached
      if (videoRef.current.srcObject !== streamRef.current && streamRef.current) {
        videoRef.current.srcObject = streamRef.current
        videoRef.current.play().catch(() => {})
        await new Promise(r => setTimeout(r, 200))
      }
      result = await faceapi
        .detectSingleFace(videoRef.current, options)
        .withFaceLandmarks(true)
        .withFaceDescriptor()
      if (result) break
    }

    if (!result) {
      setStage("failed")
      setStatusMsg("No face detected — check lighting and retry")
      return
    }

    setConfidence(Math.round(result.detection.score * 100))
    const descriptor = Array.from(result.descriptor) as number[]
    setStage("verifying")
    setStatusMsg("Verifying identity...")

    const res = await fetch("/api/security/face", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "verify", descriptor }),
    })

    if (res.ok) {
      setStage("success")
      setStatusMsg("Identity confirmed — access granted")
      streamRef.current?.getTracks().forEach(t => t.stop())
      // Write verified flag IMMEDIATELY before any async/timeout so a cookie-triggered
      // reload finds it in sessionStorage and skips the gate
      sessionStorage.setItem("nx_verified", "1")
      setTimeout(onVerified, 900)
      return
    }

    if (res.status === 404) {
      setStage("enrolling")
      setStatusMsg("First access — enrolling biometrics...")
      const enrollRes = await fetch("/api/security/face", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "enroll", descriptor }),
      })
      if (enrollRes.ok) {
        setStage("success")
        setStatusMsg("Biometrics enrolled — welcome to Nexus")
        streamRef.current?.getTracks().forEach(t => t.stop())
        sessionStorage.setItem("nx_verified", "1")
        setTimeout(onVerified, 900)
      } else {
        setStage("failed")
        setStatusMsg("Enrollment failed — retry or use passcode")
      }
      return
    }

    setStage("failed")
    setStatusMsg("Identity mismatch — access denied")
  }, [stage, onVerified])

  async function handlePasscode(e: React.FormEvent) {
    e.preventDefault()
    if (!passcode.trim()) return
    setPassStatus("checking")
    const res = await fetch("/api/passphrase", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ passphrase: passcode }),
    })
    if (res.ok) {
      setStage("success")
      setStatusMsg("Access granted")
      // Write immediately so a cookie-triggered reload doesn't re-show the gate
      sessionStorage.setItem("nx_verified", "1")
      setTimeout(onVerified, 800)
    } else {
      setPassStatus("denied")
      setPasscode("")
      setTimeout(() => setPassStatus("idle"), 2500)
    }
  }

  function switchToFace() {
    setTab("face")
    // If camera was stopped or never started, reinit
    if (!streamRef.current || streamRef.current.getTracks().every(t => t.readyState === "ended")) {
      modelsLoadedRef.current = true // models already loaded, skip re-downloading
      initFaceAuth()
    } else if (stage === "failed" || stage === "no_camera") {
      setStage("ready")
      setStatusMsg("Face the camera — press SCAN to identify")
      // Re-attach stream in case it was disconnected
      const video = videoRef.current
      if (video && streamRef.current) {
        video.srcObject = streamRef.current
        video.play().catch(() => {})
      }
    }
  }

  const isScanning = ["scanning", "verifying", "enrolling"].includes(stage)
  const cyan = "var(--nexus-cyan, oklch(0.75 0.18 200))"

  return (
    <div className="fixed inset-0 z-[200] bg-background flex flex-col overflow-hidden">
      {/* Top HUD bar */}
      <header className="flex items-center justify-between px-8 py-4 border-b border-border/50 shrink-0">
        <div className="flex items-center gap-3">
          <div className="w-1.5 h-1.5 rounded-full animate-pulse" style={{ background: cyan }} />
          <span className="font-mono text-[10px] tracking-[0.2em] uppercase" style={{ color: cyan }}>
            Nexus // Identity Verification Required
          </span>
        </div>
        <div className="flex items-center gap-6">
          <span className="font-mono text-[10px] tracking-widest text-muted-foreground">SESSION LOCKED</span>
          <span className="font-mono text-[10px] tracking-widest text-muted-foreground tabular-nums">{time}</span>
        </div>
      </header>

      {/* Main */}
      <main className="flex-1 flex items-center justify-center p-6 relative">
        <div className="absolute top-8 left-8 w-10 h-10 border-t border-l" style={{ borderColor: `oklch(0.75 0.18 200 / 0.3)` }} />
        <div className="absolute top-8 right-8 w-10 h-10 border-t border-r" style={{ borderColor: `oklch(0.75 0.18 200 / 0.3)` }} />
        <div className="absolute bottom-8 left-8 w-10 h-10 border-b border-l" style={{ borderColor: `oklch(0.75 0.18 200 / 0.3)` }} />
        <div className="absolute bottom-8 right-8 w-10 h-10 border-b border-r" style={{ borderColor: `oklch(0.75 0.18 200 / 0.3)` }} />

        <div className="relative z-10 w-full max-w-sm">
          {/* Title */}
          <div className="text-center mb-6">
            <p className="font-mono text-[10px] tracking-[0.3em] uppercase mb-1" style={{ color: cyan }}>Nexus</p>
            <p className="font-mono text-[9px] tracking-widest text-muted-foreground/60 uppercase">Re-verify to access the platform</p>
          </div>

          {/* Card */}
          <div className="relative overflow-hidden" style={{
            background: "oklch(0.10 0.015 240)",
            border: `1px solid oklch(0.75 0.18 200 / 0.25)`,
            boxShadow: "0 0 40px oklch(0.75 0.18 200 / 0.08)",
          }}>
            <div className="absolute top-0 left-0 w-4 h-4 border-t-2 border-l-2" style={{ borderColor: `oklch(0.75 0.18 200 / 0.6)` }} />
            <div className="absolute top-0 right-0 w-4 h-4 border-t-2 border-r-2" style={{ borderColor: `oklch(0.75 0.18 200 / 0.6)` }} />
            <div className="absolute bottom-0 left-0 w-4 h-4 border-b-2 border-l-2" style={{ borderColor: `oklch(0.75 0.18 200 / 0.6)` }} />
            <div className="absolute bottom-0 right-0 w-4 h-4 border-b-2 border-r-2" style={{ borderColor: `oklch(0.75 0.18 200 / 0.6)` }} />

            {/* Tabs */}
            <div className="flex border-b border-border/50">
              <button
                type="button"
                onClick={switchToFace}
                className="flex-1 flex items-center justify-center gap-2 py-3.5 font-mono text-[10px] tracking-widest uppercase transition-colors"
                style={{
                  color: tab === "face" ? cyan : "var(--muted-foreground)",
                  borderBottom: tab === "face" ? `2px solid ${cyan}` : "2px solid transparent",
                  marginBottom: "-1px",
                }}
              >
                <Scan size={12} /> Biometric
              </button>
              <button
                type="button"
                onClick={() => setTab("passcode")}
                className="flex-1 flex items-center justify-center gap-2 py-3.5 font-mono text-[10px] tracking-widest uppercase transition-colors"
                style={{
                  color: tab === "passcode" ? cyan : "var(--muted-foreground)",
                  borderBottom: tab === "passcode" ? `2px solid ${cyan}` : "2px solid transparent",
                  marginBottom: "-1px",
                }}
              >
                <KeyRound size={12} /> Passcode
              </button>
            </div>

            <div className="p-6">
              {/* ── Face tab ── */}
              {tab === "face" && (
                <div className="flex flex-col gap-4">
                  {/* Camera viewport — video is ALWAYS in DOM, just hidden on passcode tab */}
                  <div className="relative overflow-hidden bg-black" style={{ aspectRatio: "4/3", border: `1px solid oklch(0.75 0.18 200 / 0.2)` }}>
                    <div className="absolute top-2 left-2 w-5 h-5 border-t-2 border-l-2 z-10" style={{ borderColor: cyan }} />
                    <div className="absolute top-2 right-2 w-5 h-5 border-t-2 border-r-2 z-10" style={{ borderColor: cyan }} />
                    <div className="absolute bottom-2 left-2 w-5 h-5 border-b-2 border-l-2 z-10" style={{ borderColor: cyan }} />
                    <div className="absolute bottom-2 right-2 w-5 h-5 border-b-2 border-r-2 z-10" style={{ borderColor: cyan }} />

                    {/* The video element — always rendered, never conditionally mounted */}
                    <video
                      ref={videoRef}
                      className="w-full h-full object-cover"
                      style={{ transform: "scaleX(-1)" }}
                      muted
                      playsInline
                      autoPlay
                    />

                    {/* Loading overlay */}
                    {stage === "loading" && (
                      <div className="absolute inset-0 bg-black/80 flex flex-col items-center justify-center gap-4 z-20">
                        <Loader2 size={20} className="animate-spin" style={{ color: cyan }} />
                        <div className="w-36">
                          <div className="flex justify-between mb-1">
                            <span className="font-mono text-[8px] text-muted-foreground tracking-widest uppercase">Loading</span>
                            <span className="font-mono text-[8px] tabular-nums" style={{ color: cyan }}>{loadProgress}%</span>
                          </div>
                          <div className="h-0.5 bg-border">
                            <div className="h-full transition-all duration-500" style={{ width: `${loadProgress}%`, background: cyan }} />
                          </div>
                        </div>
                      </div>
                    )}

                    {/* Scan sweep */}
                    {isScanning && (
                      <div className="absolute inset-0 overflow-hidden pointer-events-none z-10">
                        <div className="absolute w-full h-0.5 animate-bounce" style={{ background: `${cyan}`, opacity: 0.7, boxShadow: `0 0 8px ${cyan}` }} />
                      </div>
                    )}

                    {/* Success overlay */}
                    {stage === "success" && (
                      <div className="absolute inset-0 flex items-center justify-center z-20" style={{ background: "oklch(0.65 0.18 155 / 0.15)", border: "2px solid oklch(0.65 0.18 155)" }}>
                        <CheckCircle2 size={44} style={{ color: "oklch(0.65 0.18 155)" }} />
                      </div>
                    )}

                    {/* Failed overlay */}
                    {stage === "failed" && (
                      <div className="absolute inset-0 flex items-center justify-center z-20" style={{ background: "oklch(0.62 0.22 25 / 0.15)", border: "2px solid oklch(0.62 0.22 25)" }}>
                        <XCircle size={44} style={{ color: "oklch(0.62 0.22 25)" }} />
                      </div>
                    )}

                    {/* No camera */}
                    {stage === "no_camera" && (
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
                        <span className="font-mono text-[8px] tabular-nums" style={{ color: cyan }}>{confidence}%</span>
                      </div>
                      <div className="h-0.5 bg-border">
                        <div className="h-full transition-all" style={{ width: `${confidence}%`, background: cyan }} />
                      </div>
                    </div>
                  )}

                  {/* Status */}
                  <p className="font-mono text-[10px] tracking-widest text-center uppercase" style={{
                    color: stage === "success" ? "oklch(0.65 0.18 155)" : stage === "failed" ? "oklch(0.62 0.22 25)" : "var(--muted-foreground)"
                  }}>
                    {statusMsg || "—"}
                  </p>

                  {/* Actions */}
                  {stage === "ready" && (
                    <button type="button" onClick={runScan}
                      className="w-full py-2.5 font-mono text-[10px] tracking-[0.2em] uppercase flex items-center justify-center gap-2 transition-all"
                      style={{ background: "oklch(0.75 0.18 200 / 0.12)", border: `1px solid oklch(0.75 0.18 200 / 0.5)`, color: cyan }}>
                      <Scan size={13} /> Scan
                    </button>
                  )}

                  {stage === "failed" && (
                    <div className="flex flex-col gap-2">
                      <button type="button"
                        onClick={() => { setStage("ready"); setConfidence(0); setStatusMsg("Face the camera — press SCAN to identify") }}
                        className="w-full py-2.5 font-mono text-[10px] tracking-[0.2em] uppercase border border-border text-muted-foreground hover:text-foreground transition-colors flex items-center justify-center gap-2">
                        Retry scan
                      </button>
                      <button type="button" onClick={() => setTab("passcode")}
                        className="font-mono text-[9px] text-muted-foreground/40 hover:text-muted-foreground/70 transition-colors tracking-widest text-center">
                        Switch to passcode
                      </button>
                    </div>
                  )}

                  {isScanning && (
                    <div className="w-full py-2.5 font-mono text-[10px] tracking-[0.2em] uppercase text-center text-muted-foreground/50 select-none">
                      Scanning...
                    </div>
                  )}
                </div>
              )}

              {/* ── Passcode tab ── */}
              {tab === "passcode" && (
                <form onSubmit={handlePasscode} className="flex flex-col gap-4">
                  <p className="font-mono text-[10px] tracking-widest text-center text-muted-foreground/60 uppercase">Enter passcode to authenticate</p>
                  <input
                    type="password"
                    value={passcode}
                    onChange={e => setPasscode(e.target.value)}
                    placeholder="••••••••••"
                    autoFocus
                    autoComplete="current-password"
                    className="w-full bg-transparent border border-border/60 px-4 py-3 font-mono text-sm text-center tracking-widest focus:outline-none focus:border-[var(--nexus-cyan)]/60 placeholder:text-muted-foreground/30"
                  />
                  {passStatus === "denied" && (
                    <p className="font-mono text-[10px] tracking-widest text-center uppercase" style={{ color: "oklch(0.62 0.22 25)" }}>
                      Invalid passcode — try again or use face scan
                    </p>
                  )}
                  <button type="submit" disabled={passStatus === "checking" || !passcode.trim()}
                    className="w-full py-2.5 font-mono text-[10px] tracking-[0.2em] uppercase flex items-center justify-center gap-2 transition-all disabled:opacity-40"
                    style={{ background: "oklch(0.75 0.18 200 / 0.12)", border: `1px solid oklch(0.75 0.18 200 / 0.5)`, color: cyan }}>
                    <KeyRound size={13} />
                    {passStatus === "checking" ? "Verifying..." : "Authenticate"}
                  </button>
                  <button type="button" onClick={switchToFace}
                    className="font-mono text-[9px] text-muted-foreground/40 hover:text-muted-foreground/70 transition-colors tracking-widest text-center">
                    Switch to face scan
                  </button>
                </form>
              )}
            </div>
          </div>

          <p className="mt-6 font-mono text-[9px] tracking-[0.2em] text-muted-foreground/30 uppercase text-center">
            Unauthorized access is prohibited and monitored
          </p>
        </div>
      </main>

      {/* Bottom bar */}
      <footer className="flex items-center justify-between px-8 py-3 border-t border-border/50 shrink-0">
        <span className="font-mono text-[9px] tracking-widest text-muted-foreground/40 uppercase">End-to-end encrypted</span>
        <span className="font-mono text-[9px] tracking-widest text-muted-foreground/40 uppercase">All sessions logged</span>
      </footer>
    </div>
  )
}
