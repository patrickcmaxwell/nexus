"use client"

import { useState, useEffect, useRef, useCallback } from "react"

type Stage = "loading_models" | "ready" | "scanning" | "verifying" | "enrolling" | "success" | "failed" | "no_camera" | "passphrase"

export default function FaceScanModal({ onClose }: { onClose: () => void }) {
  const videoRef = useRef<HTMLVideoElement>(null)
  const streamRef = useRef<MediaStream | null>(null)
  const faceapiRef = useRef<any>(null)

  const [stage, setStage] = useState<Stage>("loading_models")
  const [statusMsg, setStatusMsg] = useState("LOADING BIOMETRIC MODELS...")
  const [loadProgress, setLoadProgress] = useState(0)
  const [confidence, setConfidence] = useState(0)
  const [passphrase, setPassphrase] = useState("")
  const [passStatus, setPassStatus] = useState<"idle" | "checking" | "denied">("idle")

  // Boot: load models then open camera automatically
  useEffect(() => {
    let cancelled = false

    async function boot() {
      try {
        const faceapi = await import("@vladmandic/face-api")
        const MODEL_URL = "https://cdn.jsdelivr.net/npm/@vladmandic/face-api/model"

        setLoadProgress(5)
        await faceapi.nets.tinyFaceDetector.loadFromUri(MODEL_URL)
        if (cancelled) return
        setLoadProgress(38)
        setStatusMsg("LOADING LANDMARK MODEL...")

        await faceapi.nets.faceLandmark68TinyNet.loadFromUri(MODEL_URL)
        if (cancelled) return
        setLoadProgress(72)
        setStatusMsg("LOADING RECOGNITION MODEL...")

        await faceapi.nets.faceRecognitionNet.loadFromUri(MODEL_URL)
        if (cancelled) return
        setLoadProgress(100)
        faceapiRef.current = faceapi

        setStatusMsg("ACTIVATING CAMERA...")
        const stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: "user", width: 640, height: 480 },
        })
        if (cancelled) { stream.getTracks().forEach((t) => t.stop()); return }

        streamRef.current = stream
        if (videoRef.current) {
          videoRef.current.srcObject = stream
          await videoRef.current.play()
        }

        setStage("ready")
        setStatusMsg("FACE THE CAMERA — PRESS SCAN TO IDENTIFY")
      } catch (err: any) {
        if (cancelled) return
        if (err?.name === "NotAllowedError" || err?.name === "NotFoundError") {
          setStage("no_camera")
          setStatusMsg("CAMERA UNAVAILABLE — USE PASSPHRASE FALLBACK")
        } else {
          setStage("no_camera")
          setStatusMsg("MODEL LOAD FAILED — USE PASSPHRASE FALLBACK")
        }
      }
    }

    boot()
    return () => {
      cancelled = true
      streamRef.current?.getTracks().forEach((t) => t.stop())
    }
  }, [])

  const runScan = useCallback(async () => {
    if (!faceapiRef.current || !videoRef.current || stage !== "ready") return
    setStage("scanning")
    setConfidence(0)
    setStatusMsg("SCANNING — HOLD STILL...")

    const faceapi = faceapiRef.current
    const options = new faceapi.TinyFaceDetectorOptions({ inputSize: 320, scoreThreshold: 0.45 })

    let result = null
    for (let i = 0; i < 8; i++) {
      setStatusMsg(`SCANNING... ATTEMPT ${i + 1} OF 8`)
      await new Promise((r) => setTimeout(r, 1000))
      if (!videoRef.current) break
      result = await faceapi
        .detectSingleFace(videoRef.current, options)
        .withFaceLandmarks(true)
        .withFaceDescriptor()
      if (result) break
    }

    if (!result) {
      setStage("failed")
      setStatusMsg("NO FACE DETECTED — CHECK LIGHTING AND RETRY")
      return
    }

    setConfidence(Math.round(result.detection.score * 100))
    const descriptor = Array.from(result.descriptor) as number[]

    setStage("verifying")
    setStatusMsg("CROSS-REFERENCING BIOMETRIC DATABASE...")

    const verifyRes = await fetch("/api/security/face", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "verify", descriptor }),
    })

    if (verifyRes.ok) {
      setStage("success")
      setStatusMsg("IDENTITY CONFIRMED — ACCESS GRANTED")
      // Use server-side redirect so cookie is sent with the navigation request
      setTimeout(() => { window.location.href = "/api/security/enter" }, 1200)
      return
    }

    if (verifyRes.status === 404) {
      setStage("enrolling")
      setStatusMsg("FIRST ACCESS — ENROLLING BIOMETRIC REFERENCE...")
      const enrollRes = await fetch("/api/security/face", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "enroll", descriptor }),
      })
      if (enrollRes.ok) {
        setStage("success")
        setStatusMsg("BIOMETRIC ENROLLED — WELCOME, DIRECTOR")
        setTimeout(() => { window.location.href = "/api/security/enter" }, 1200)
      } else {
        setStage("failed")
        setStatusMsg("ENROLLMENT FAILED — RETRY OR USE PASSPHRASE")
      }
      return
    }

    setStage("failed")
    setStatusMsg("IDENTITY MISMATCH — ACCESS DENIED")
  }, [stage])

  async function handlePassphrase(e: React.FormEvent) {
    e.preventDefault()
    if (!passphrase.trim()) return
    setPassStatus("checking")
    const res = await fetch("/api/passphrase", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ passphrase }),
    })
    if (res.ok) {
      setStage("success")
      setStatusMsg("PASSPHRASE ACCEPTED — ACCESS GRANTED")
      setTimeout(() => { window.location.href = "/api/security/enter" }, 1200)
    } else {
      setPassStatus("denied")
      setPassphrase("")
      setTimeout(() => setPassStatus("idle"), 2500)
    }
  }

  function retryCamera() {
    setStage("ready")
    setConfidence(0)
    setStatusMsg("FACE THE CAMERA — PRESS SCAN TO IDENTIFY")
  }

  const scanning = stage === "scanning" || stage === "verifying" || stage === "enrolling"
  const statusColor =
    stage === "success" ? "text-green-400"
    : stage === "failed" ? "text-hud-red"
    : "text-hud-gold"

  return (
    <div
      className="fixed inset-0 z-[100] flex items-center justify-center bg-background/85 backdrop-blur-sm p-6"
      onClick={(e) => { if (e.target === e.currentTarget && !scanning && stage !== "success") onClose() }}
    >
      <div className="hud-border bg-card w-full max-w-sm relative scan-line" onClick={(e) => e.stopPropagation()}>
        {/* Modal header */}
        <div className="flex items-center justify-between px-5 py-3 border-b border-border">
          <div className="flex items-center gap-2">
            <div className="w-1.5 h-1.5 rounded-full bg-hud-red animate-pulse-glow" />
            <span className="font-mono text-[10px] text-hud-gold tracking-widest" style={{ fontFamily: "var(--font-orbitron)" }}>
              BIOMETRIC IDENTIFICATION
            </span>
          </div>
          {stage !== "success" && !scanning && (
            <button
              onClick={onClose}
              className="font-mono text-[10px] text-muted-foreground hover:text-hud-red transition-colors"
              style={{ fontFamily: "var(--font-orbitron)" }}
            >
              [ESC]
            </button>
          )}
        </div>

        <div className="p-5">
          {/* Loading bar */}
          {stage === "loading_models" && (
            <div className="mb-4">
              <div className="h-0.5 bg-border mb-1.5">
                <div className="h-full bg-hud-red transition-all duration-500" style={{ width: `${loadProgress}%` }} />
              </div>
              <p className="font-mono text-[9px] text-center text-muted-foreground tracking-widest">{loadProgress}% — INITIALIZING</p>
            </div>
          )}

          {/* Camera viewport */}
          {stage !== "passphrase" && (
            <div className="relative mb-4" style={{ aspectRatio: "4/3" }}>
              {/* HUD corners */}
              <div className="absolute top-0 left-0 w-6 h-6 border-t-2 border-l-2 border-hud-red z-10" />
              <div className="absolute top-0 right-0 w-6 h-6 border-t-2 border-r-2 border-hud-red z-10" />
              <div className="absolute bottom-0 left-0 w-6 h-6 border-b-2 border-l-2 border-hud-red z-10" />
              <div className="absolute bottom-0 right-0 w-6 h-6 border-b-2 border-r-2 border-hud-red z-10" />

              {/* Reticle */}
              <div className="absolute inset-0 flex items-center justify-center pointer-events-none z-10">
                <div className="w-14 h-14 rounded-full border border-hud-red/40" />
                <div className="absolute w-px h-3 bg-hud-red/40" />
                <div className="absolute w-3 h-px bg-hud-red/40" />
              </div>

              <video
                ref={videoRef}
                className="w-full h-full object-cover bg-black"
                style={{ transform: "scaleX(-1)", filter: "grayscale(15%) contrast(1.1)" }}
                muted
                playsInline
              />

              {/* Scan line animation */}
              {scanning && (
                <div className="absolute inset-0 overflow-hidden pointer-events-none z-20">
                  <div
                    className="absolute w-full h-0.5 bg-hud-red/70 shadow-[0_0_8px_2px_oklch(0.55_0.22_25/0.5)]"
                    style={{ animation: "hud-scan 1.8s linear infinite" }}
                  />
                </div>
              )}

              {/* Success overlay */}
              {stage === "success" && (
                <div className="absolute inset-0 bg-green-400/10 border-2 border-green-400 flex items-center justify-center z-20">
                  <div className="text-center">
                    <div className="text-green-400 text-4xl font-bold mb-1">✓</div>
                    <p className="font-mono text-[10px] text-green-400 tracking-widest">ACCESS GRANTED</p>
                  </div>
                </div>
              )}

              {/* Failed overlay */}
              {stage === "failed" && (
                <div className="absolute inset-0 bg-hud-red/10 border-2 border-hud-red flex items-center justify-center z-20">
                  <div className="text-center">
                    <div className="text-hud-red text-4xl font-bold mb-1">✗</div>
                    <p className="font-mono text-[10px] text-hud-red tracking-widest">ACCESS DENIED</p>
                  </div>
                </div>
              )}

              {/* Loading overlay */}
              {stage === "loading_models" && (
                <div className="absolute inset-0 bg-card flex items-center justify-center z-20">
                  <div className="w-7 h-7 border-2 border-hud-red border-t-transparent rounded-full animate-spin" />
                </div>
              )}

              {/* No camera overlay */}
              {stage === "no_camera" && (
                <div className="absolute inset-0 bg-card border border-hud-red/40 flex items-center justify-center z-20">
                  <p className="font-mono text-[10px] text-hud-red text-center px-4 tracking-widest leading-loose">
                    CAMERA<br />UNAVAILABLE
                  </p>
                </div>
              )}
            </div>
          )}

          {/* Confidence meter */}
          {confidence > 0 && stage !== "passphrase" && (
            <div className="mb-3">
              <div className="flex justify-between mb-1">
                <span className="font-mono text-[9px] text-muted-foreground tracking-widest">CONFIDENCE</span>
                <span className="font-mono text-[9px] text-hud-gold">{confidence}%</span>
              </div>
              <div className="h-0.5 bg-border">
                <div className="h-full bg-hud-gold transition-all duration-500" style={{ width: `${confidence}%` }} />
              </div>
            </div>
          )}

          {/* Status */}
          <p className={`font-mono text-[11px] tracking-widest text-center mb-4 ${scanning ? "animate-pulse-glow" : ""} ${statusColor}`}>
            {statusMsg}
          </p>

          {/* Actions */}
          {stage === "ready" && (
            <button
              onClick={runScan}
              className="w-full hud-border hud-glow-red text-hud-red font-mono text-sm py-3 hover:bg-[oklch(0.55_0.22_25/0.1)] transition-colors tracking-widest active:scale-95"
              style={{ fontFamily: "var(--font-orbitron)" }}
            >
              INITIATE FACE SCAN
            </button>
          )}

          {stage === "failed" && (
            <div className="flex flex-col gap-2">
              <button
                onClick={retryCamera}
                className="w-full hud-border text-hud-gold font-mono text-sm py-3 hover:bg-hud-gold/10 transition-colors tracking-widest"
                style={{ fontFamily: "var(--font-orbitron)" }}
              >
                RETRY SCAN
              </button>
            </div>
          )}

          {scanning && (
            <div className="w-full hud-border text-muted-foreground font-mono text-sm py-3 text-center tracking-widest opacity-40 select-none">
              SCANNING...
            </div>
          )}

          {/* Passphrase fallback */}
          {stage === "passphrase" || stage === "no_camera" ? (
            <form onSubmit={handlePassphrase} className="flex flex-col gap-3">
              <input
                type="password"
                value={passphrase}
                onChange={(e) => setPassphrase(e.target.value)}
                placeholder="••••••••••"
                autoComplete="off"
                className={`w-full bg-input hud-border px-4 py-3 font-mono text-sm text-center tracking-widest focus:outline-none focus:ring-1 focus:ring-hud-gold placeholder:text-muted-foreground/30 ${passStatus === "denied" ? "ring-1 ring-hud-red" : ""}`}
                style={{ fontFamily: "var(--font-orbitron)" }}
              />
              {passStatus === "denied" && (
                <p className="font-mono text-[10px] text-hud-red tracking-widest text-center animate-pulse-glow">INVALID PASSPHRASE</p>
              )}
              <button
                type="submit"
                disabled={passStatus === "checking" || !passphrase.trim()}
                className="hud-border px-8 py-3 font-mono text-sm text-hud-gold hover:bg-hud-gold/10 transition-colors tracking-widest disabled:opacity-40 disabled:cursor-not-allowed"
                style={{ fontFamily: "var(--font-orbitron)" }}
              >
                {passStatus === "checking" ? "VERIFYING..." : "SUBMIT PASSPHRASE"}
              </button>
              {stage === "passphrase" && (
                <button
                  type="button"
                  onClick={retryCamera}
                  className="font-mono text-[9px] text-muted-foreground/40 hover:text-muted-foreground transition-colors tracking-widest text-center"
                >
                  BACK TO FACE SCAN
                </button>
              )}
            </form>
          ) : (
            (stage === "ready" || stage === "failed") && (
              <div className="mt-4 text-center">
                <button
                  onClick={() => setStage("passphrase")}
                  className="font-mono text-[9px] text-muted-foreground/30 hover:text-muted-foreground/60 transition-colors tracking-widest underline underline-offset-2"
                >
                  USE PASSPHRASE INSTEAD
                </button>
              </div>
            )
          )}
        </div>
      </div>
    </div>
  )
}
