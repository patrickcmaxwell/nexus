"use client"

import { Suspense, useEffect, useRef, useState, useCallback } from "react"
import { useRouter, useSearchParams } from "next/navigation"

type Stage = "loading_models" | "ready" | "scanning" | "enrolling" | "verifying" | "success" | "failed" | "no_camera"

// Embedded mode (?embedded=1) is for the Lumen desktop WebView wrapper.
// Strips redundant page chrome (the host card already shows LUMEN branding,
// "Sign in" headers, etc.) and auto-starts the scan since the user already
// chose face mode by tapping the FACE toggle. Standalone mode keeps the
// full-screen HUD layout for direct browser use.
export default function FacePage() {
  // Next 16 requires useSearchParams to live under a Suspense boundary
  // so client pages can be statically prerendered without bailing.
  return (
    <Suspense fallback={null}>
      <FacePageInner />
    </Suspense>
  )
}

function FacePageInner() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const embedded = searchParams.get("embedded") === "1"
  const videoRef = useRef<HTMLVideoElement>(null)
  const streamRef = useRef<MediaStream | null>(null)
  const faceapiRef = useRef<any>(null)

  const [stage, setStage] = useState<Stage>("loading_models")
  const [statusMsg, setStatusMsg] = useState("LOADING BIOMETRIC MODELS...")
  const [loadProgress, setLoadProgress] = useState(0)
  const [confidence, setConfidence] = useState(0)

  // Step 1: Load models on mount
  useEffect(() => {
    async function loadModels() {
      try {
        setStatusMsg("LOADING MODEL 1/3 — FACE DETECTOR...")
        setLoadProgress(10)
        const faceapi = await import("@vladmandic/face-api")
        const MODEL_URL = "/models"

        await faceapi.nets.tinyFaceDetector.loadFromUri(MODEL_URL)
        setLoadProgress(40)
        setStatusMsg("LOADING MODEL 2/3 — LANDMARKS...")

        await faceapi.nets.faceLandmark68TinyNet.loadFromUri(MODEL_URL)
        setLoadProgress(70)
        setStatusMsg("LOADING MODEL 3/3 — RECOGNITION NET...")

        await faceapi.nets.faceRecognitionNet.loadFromUri(MODEL_URL)
        setLoadProgress(100)

        faceapiRef.current = faceapi

        // Start camera silently in the background
        try {
          const stream = await navigator.mediaDevices.getUserMedia({
            video: { facingMode: "user", width: 640, height: 480 },
          })
          streamRef.current = stream
          if (videoRef.current) {
            videoRef.current.srcObject = stream
            await videoRef.current.play()
          }
          setStage("ready")
          setStatusMsg("CAMERA READY — PRESS SCAN TO VERIFY IDENTITY")
        } catch {
          setStage("no_camera")
          setStatusMsg("CAMERA ACCESS DENIED")
        }
      } catch {
        setStage("no_camera")
        setStatusMsg("FAILED TO LOAD MODELS — CHECK CONNECTION")
      }
    }
    loadModels()
    return () => { streamRef.current?.getTracks().forEach((t) => t.stop()) }
  }, [])

  const runScan = useCallback(async () => {
    if (!faceapiRef.current || !videoRef.current) return
    setStage("scanning")
    setStatusMsg("SCANNING — LOOK DIRECTLY AT CAMERA...")
    setConfidence(0)

    const faceapi = faceapiRef.current
    const options = new faceapi.TinyFaceDetectorOptions({ inputSize: 320, scoreThreshold: 0.45 })

    let result = null
    for (let attempt = 0; attempt < 6; attempt++) {
      setStatusMsg(`SCANNING BIOMETRICS... (${attempt + 1}/6)`)
      await new Promise((r) => setTimeout(r, 1200))
      result = await faceapi
        .detectSingleFace(videoRef.current, options)
        .withFaceLandmarks(true)
        .withFaceDescriptor()
      if (result) break
    }

    if (!result) {
      setStage("failed")
      setStatusMsg("NO FACE DETECTED — ENSURE GOOD LIGHTING AND RETRY")
      return
    }

    setConfidence(Math.round(result.detection.score * 100))
    const descriptor = Array.from(result.descriptor) as number[]

    // Try verify first
    setStage("verifying")
    setStatusMsg("VERIFYING IDENTITY...")
    const verifyRes = await fetch("/api/security/face", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "verify", descriptor }),
    })

    if (verifyRes.ok) {
      setStage("success")
      setStatusMsg("IDENTITY CONFIRMED — ACCESS GRANTED")
      setTimeout(() => { window.location.href = "/dashboard" }, 1500)
      return
    }

    if (verifyRes.status === 404) {
      // No reference stored yet — first login, enroll now
      setStage("enrolling")
      setStatusMsg("FIRST LOGIN — ENROLLING YOUR FACE REFERENCE...")
      const enrollRes = await fetch("/api/security/face", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "enroll", descriptor }),
      })
      if (enrollRes.ok) {
        setStage("success")
        setStatusMsg("FACE ENROLLED AND CONFIRMED — WELCOME")
        setTimeout(() => { window.location.href = "/dashboard" }, 2000)
      } else {
        setStage("failed")
        setStatusMsg("ENROLLMENT FAILED — TRY AGAIN")
      }
      return
    }

    // Mismatch
    setStage("failed")
    setStatusMsg("IDENTITY MISMATCH — ACCESS DENIED")
  }, [router])

  const handleRetry = () => {
    setStage("ready")
    setConfidence(0)
    setStatusMsg("CAMERA READY — PRESS SCAN TO VERIFY IDENTITY")
  }

  // Auto-start scan in embedded mode. The user already opted in by selecting
  // FACE mode in the Lumen desktop wrapper, so requiring a second "INITIATE
  // SCAN" button click is friction with no protective value.
  useEffect(() => {
    if (embedded && stage === "ready") {
      runScan()
    }
  }, [embedded, stage, runScan])

  const statusColor =
    stage === "success" ? "text-green-400"
    : stage === "failed" ? "text-destructive"
    : stage === "enrolling" ? "text-primary"
    : "text-primary"

  const scanning = stage === "scanning" || stage === "verifying" || stage === "enrolling"

  return (
    <div className={
      embedded
        ? "min-h-full bg-transparent flex items-center justify-center"
        : "min-h-screen bg-background flex items-center justify-center "
    }>
      <div className={embedded ? "w-full px-4 py-3" : "w-full max-w-md px-6"}>

        {/* Header — hidden in embedded mode (host card supplies the branding) */}
        {!embedded && (
          <div className="text-center mb-8">
            <div className="w-12 h-12 border border-destructive/40 mx-auto mb-4 flex items-center justify-center">
              <span className="text-destructive font-bold text-sm animate-pulse-glow">MN</span>
            </div>
            <p className="text-xs text-muted-foreground mb-1">MAXWELL NEXUS SECURITY</p>
            <h1 className="text-primary text-xl font-bold ">
              BIOMETRIC VERIFICATION
            </h1>
            <p className="text-xs text-muted-foreground mt-2">LAYER 2 OF 2 — REQUIRED ON EVERY ENTRY</p>
          </div>
        )}

        {/* Model loading progress bar */}
        {stage === "loading_models" && (
          <div className="mb-6">
            <div className="h-1 bg-border mb-2">
              <div
                className="h-full bg-destructive transition-all duration-700"
                style={{ width: `${loadProgress}%` }}
              />
            </div>
            <p className="text-xs text-center text-muted-foreground">{loadProgress}% — MODELS LOADING</p>
          </div>
        )}

        {/* Camera frame */}
        <div className="relative mx-auto mb-6" style={{ width: 280, height: 280 }}>
          {/* HUD corners */}
          <div className="absolute top-0 left-0 w-8 h-8 border-t-2 border-l-2 border-destructive z-10" />
          <div className="absolute top-0 right-0 w-8 h-8 border-t-2 border-r-2 border-destructive z-10" />
          <div className="absolute bottom-0 left-0 w-8 h-8 border-b-2 border-l-2 border-destructive z-10" />
          <div className="absolute bottom-0 right-0 w-8 h-8 border-b-2 border-r-2 border-destructive z-10" />

          <video
            ref={videoRef}
            className="w-full h-full object-cover bg-black"
            style={{ transform: "scaleX(-1)", filter: "grayscale(20%) contrast(1.1)" }}
            muted
            playsInline
          />

          {/* Scan line while scanning */}
          {scanning && (
            <div className="absolute inset-0 overflow-hidden pointer-events-none z-10">
              <div className="absolute w-full h-0.5 bg-primary/60 animate-pulse" />
            </div>
          )}

          {/* Success overlay */}
          {stage === "success" && (
            <div className="absolute inset-0 bg-green-400/10 border-2 border-green-400 flex items-center justify-center z-10">
              <span className="text-green-400 text-5xl font-bold">✓</span>
            </div>
          )}

          {/* Failed overlay */}
          {stage === "failed" && (
            <div className="absolute inset-0 bg-destructive/10 border-2 border-destructive flex items-center justify-center z-10">
              <span className="text-destructive text-5xl font-bold">✗</span>
            </div>
          )}

          {/* Loading placeholder */}
          {stage === "loading_models" && (
            <div className="absolute inset-0 bg-card flex items-center justify-center z-10">
              <div className="text-center">
                <div className="w-8 h-8 border-2 border-destructive border-t-transparent rounded-full animate-spin mx-auto mb-2" />
                <span className="text-xs text-muted-foreground">LOADING...</span>
              </div>
            </div>
          )}

          {/* No camera */}
          {stage === "no_camera" && (
            <div className="absolute inset-0 bg-card border border-destructive flex items-center justify-center z-10">
              <span className="text-xs text-destructive text-center px-4">CAMERA UNAVAILABLE</span>
            </div>
          )}
        </div>

        {/* Confidence meter */}
        {confidence > 0 && (
          <div className="mb-4">
            <div className="flex justify-between mb-1">
              <span className="text-xs text-muted-foreground">SCAN CONFIDENCE</span>
              <span className="text-xs text-primary">{confidence}%</span>
            </div>
            <div className="h-1 bg-border">
              <div className="h-full bg-primary transition-all duration-500" style={{ width: `${confidence}%` }} />
            </div>
          </div>
        )}

        {/* Status line */}
        <div className="text-center mb-6">
          <p className={`text-sm font-medium ${scanning ? "animate-pulse-glow" : ""} ${statusColor}`}>
            {statusMsg}
          </p>
        </div>

        {/* Action buttons */}
        <div className="flex flex-col gap-3">
          {stage === "ready" && (
            <button
              onClick={runScan}
              className="w-full border border-primary/40 text-primary text-sm font-medium py-4 hover:bg-[oklch(0.75_0.18_75/0.1)] transition-colors  active:scale-95"
             
            >
              INITIATE FACE SCAN
            </button>
          )}

          {scanning && (
            <div className="w-full border border-border text-muted-foreground text-sm font-medium py-4 text-center  opacity-50">
              SCANNING...
            </div>
          )}

          {stage === "failed" && (
            <button
              onClick={handleRetry}
              className="w-full border border-border text-primary text-sm font-medium py-4 hover:bg-[oklch(0.75_0.18_75/0.1)] transition-colors  active:scale-95"
             
            >
              RETRY SCAN
            </button>
          )}
        </div>

        {/* Footer — hidden in embedded mode for the same reason as the header */}
        {!embedded && (
          <div className="mt-6 text-center">
            <p className="text-xs text-muted-foreground/60">
              FACE SCAN ENABLED · STRONGLY RECOMMENDED FOR INSTANT LOGIN
            </p>
          </div>
        )}
      </div>
    </div>
  )
}
