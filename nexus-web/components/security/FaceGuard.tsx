"use client"

import { useEffect, useRef, useState } from "react"

const CHECK_INTERVAL_MS = 120_000   // Check every 2 minutes
const FIRST_CHECK_DELAY_MS = 180_000 // Wait 3 minutes after mount before first check
const MAX_CONSECUTIVE_MISSES = 5    // 5 misses = ~10 mins away before screen locks

// LockedScreen — shown when FaceGuard detects absence. Requires a real face match to resume.
function LockedScreen({
  videoRef,
  faceapiRef,
  onUnlocked,
}: {
  videoRef: React.RefObject<HTMLVideoElement | null>
  faceapiRef: React.RefObject<any>
  onUnlocked: () => void
}) {
  const [status, setStatus] = useState<"idle" | "scanning" | "failed" | "success">("idle")
  const [msg, setMsg] = useState("FACE SCAN REQUIRED TO RESUME")

  async function handleResumeScan() {
    if (!faceapiRef.current || !videoRef.current) {
      setStatus("failed")
      setMsg("CAMERA NOT READY — TRY AGAIN")
      return
    }
    setStatus("scanning")
    setMsg("SCANNING — HOLD STILL...")
    try {
      const options = new faceapiRef.current.TinyFaceDetectorOptions({ inputSize: 160, scoreThreshold: 0.4 })
      const result = await faceapiRef.current
        .detectSingleFace(videoRef.current, options)
        .withFaceLandmarks(true)
        .withFaceDescriptor()

      if (!result) {
        setStatus("failed")
        setMsg("FACE NOT DETECTED — TRY AGAIN")
        return
      }

      const descriptor = Array.from(result.descriptor) as number[]
      const res = await fetch("/api/security/face", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "verify", descriptor }),
      })

      if (res.ok) {
        setStatus("success")
        setMsg("IDENTITY CONFIRMED — RESUMING...")
        setTimeout(onUnlocked, 900)
      } else {
        setStatus("failed")
        setMsg("IDENTITY MISMATCH — ACCESS DENIED")
      }
    } catch {
      setStatus("failed")
      setMsg("SCAN ERROR — TRY AGAIN")
    }
  }

  const borderColor =
    status === "success" ? "border-hud-gold" :
    status === "failed" ? "border-hud-red" :
    status === "scanning" ? "border-hud-gold animate-pulse" :
    "border-border"

  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center backdrop-blur-xl bg-background/90">
      <div className="text-center max-w-xs w-full px-6">
        <div className={`w-24 h-24 border-2 ${borderColor} mx-auto mb-6 flex items-center justify-center transition-colors duration-300`}>
          <span className={`text-4xl ${status === "scanning" ? "text-hud-gold animate-pulse-glow" : "text-hud-red"}`}>
            {status === "success" ? "◉" : "◎"}
          </span>
        </div>
        <p className="text-hud-red font-bold tracking-widest text-sm mb-2" style={{ fontFamily: "var(--font-orbitron)" }}>
          SESSION LOCKED
        </p>
        <p className="font-mono text-[10px] text-muted-foreground tracking-widest mb-8">
          {msg}
        </p>
        {status !== "success" && (
          <button
            onClick={handleResumeScan}
            disabled={status === "scanning"}
            className="hud-border hud-glow-red px-10 py-4 font-mono text-xs tracking-widest text-hud-red hover:bg-hud-red/10 transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
            style={{ fontFamily: "var(--font-orbitron)" }}
          >
            {status === "scanning" ? "SCANNING..." : "SCAN FACE TO RESUME"}
          </button>
        )}
        {status === "failed" && (
          <p className="font-mono text-[9px] text-muted-foreground/50 mt-4 tracking-widest">
            UNAUTHORIZED ACCESS WILL BE LOGGED
          </p>
        )}
      </div>
    </div>
  )
}

export default function FaceGuard({ children }: { children: React.ReactNode }) {
  const videoRef = useRef<HTMLVideoElement>(null)
  const streamRef = useRef<MediaStream | null>(null)
  const faceapiRef = useRef<any>(null)
  const readyRef = useRef(false) // true only after models AND camera are both up
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const consecutiveMissesRef = useRef(0)

  const [isChecking, setIsChecking] = useState(false)
  const [isLocked, setIsLocked] = useState(false)

  useEffect(() => {
    let cancelled = false

    async function init() {
      try {
        const faceapi = await import("@vladmandic/face-api")
        const MODEL_URL = "https://cdn.jsdelivr.net/npm/@vladmandic/face-api/model"
        await faceapi.nets.tinyFaceDetector.loadFromUri(MODEL_URL)
        await faceapi.nets.faceLandmark68TinyNet.loadFromUri(MODEL_URL)
        await faceapi.nets.faceRecognitionNet.loadFromUri(MODEL_URL)

        if (cancelled) return
        faceapiRef.current = faceapi

        const stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: "user", width: 320, height: 240 },
        })
        if (cancelled) { stream.getTracks().forEach((t) => t.stop()); return }

        streamRef.current = stream
        if (videoRef.current) {
          videoRef.current.srcObject = stream
          await videoRef.current.play()
        }

        // Mark ready — only now do we allow checks to run
        readyRef.current = true

        // First check after a long grace period, then every 45s
        const firstTimeout = setTimeout(() => {
          if (cancelled || !readyRef.current) return
          runCheck()
          intervalRef.current = setInterval(() => {
            if (!readyRef.current) return
            runCheck()
          }, CHECK_INTERVAL_MS)
        }, FIRST_CHECK_DELAY_MS)

        return () => clearTimeout(firstTimeout)
      } catch {
        // Camera or model unavailable — silent, don't penalise
      }
    }

    init()

    return () => {
      cancelled = true
      readyRef.current = false
      if (intervalRef.current) clearInterval(intervalRef.current)
      streamRef.current?.getTracks().forEach((t) => t.stop())
    }
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  async function runCheck() {
    // Guard: bail out if not fully ready
    if (!readyRef.current || !faceapiRef.current || !videoRef.current) return

    setIsChecking(true)
    try {
      const options = new faceapiRef.current.TinyFaceDetectorOptions({
        inputSize: 160,
        scoreThreshold: 0.4, // slightly lenient for background checks
      })

      const result = await faceapiRef.current
        .detectSingleFace(videoRef.current, options)
        .withFaceLandmarks(true)
        .withFaceDescriptor()

      if (!result) {
        consecutiveMissesRef.current += 1
        if (consecutiveMissesRef.current >= MAX_CONSECUTIVE_MISSES) {
          setIsLocked(true)
        }
        return
      }

      // Face detected — reset and unlock
      consecutiveMissesRef.current = 0
      setIsLocked(false)

      const descriptor = Array.from(result.descriptor) as number[]
      const res = await fetch("/api/security/face", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "verify", descriptor }),
      })

      if (res.ok) {
        consecutiveMissesRef.current = 0
      }
      // Any error from server — skip silently, never lock
    } catch {
      // Network hiccup — don't penalise, just skip this check
    } finally {
      setIsChecking(false)
    }
  }

  return (
    <>
      {/* Hidden camera feed for background checks */}
      <video ref={videoRef} className="hidden" muted playsInline />

      {/* Subtle HUD indicator — top right */}
      <div className="fixed top-3 right-3 z-50 flex items-center gap-1.5">
        <div className={`w-1.5 h-1.5 rounded-full ${isChecking ? "bg-hud-gold animate-pulse-glow" : "bg-green-500/50"}`} />
        <span className="font-mono text-[9px] text-muted-foreground tracking-widest hidden sm:inline">
          {isChecking ? "SCANNING" : "EVE WATCH"}
        </span>
      </div>

      {/* Lock screen overlay — requires a successful face scan to resume */}
      {isLocked && (
        <LockedScreen
          videoRef={videoRef}
          faceapiRef={faceapiRef}
          onUnlocked={() => {
            consecutiveMissesRef.current = 0
            setIsLocked(false)
          }}
        />
      )}

      {children}
    </>
  )
}
