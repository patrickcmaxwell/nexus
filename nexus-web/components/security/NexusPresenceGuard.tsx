"use client"

import { useEffect, useRef, useState } from "react"
import { Scan, KeyRound, Loader2, CheckCircle2, XCircle } from "lucide-react"

const CHECK_INTERVAL_MS    = 300_000  // every 5 min
const FIRST_CHECK_DELAY_MS = 600_000  // 10 min grace on mount
const MAX_MISSES           = 12       // ~60 min of missed checks before lock

// ── Re-auth lock screen ──────────────────────────────────────────────────────
function LockScreen({
  videoRef, faceapiRef, onUnlocked,
}: {
  videoRef: React.RefObject<HTMLVideoElement | null>
  faceapiRef: React.RefObject<any>
  onUnlocked: () => void
}) {
  const [tab, setTab]         = useState<"face" | "passcode">("face")
  const [status, setStatus]   = useState<"idle" | "scanning" | "failed" | "success">("idle")
  const [msg, setMsg]         = useState("Verify your identity to continue")
  const [passcode, setPasscode] = useState("")
  const [passErr, setPassErr]   = useState(false)

  async function scanFace() {
    if (!faceapiRef.current || !videoRef.current) {
      setStatus("failed"); setMsg("Camera not ready — try passcode"); return
    }
    setStatus("scanning"); setMsg("Scanning — hold still...")
    try {
      const opts = new faceapiRef.current.TinyFaceDetectorOptions({ inputSize: 160, scoreThreshold: 0.4 })
      const result = await faceapiRef.current
        .detectSingleFace(videoRef.current, opts).withFaceLandmarks(true).withFaceDescriptor()
      if (!result) { setStatus("failed"); setMsg("Face not detected — try again"); return }
      const res = await fetch("/api/security/face", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "verify", descriptor: Array.from(result.descriptor) }),
      })
      if (res.ok) { setStatus("success"); setMsg("Identity confirmed"); setTimeout(onUnlocked, 900) }
      else { setStatus("failed"); setMsg("Identity mismatch — access denied") }
    } catch { setStatus("failed"); setMsg("Scan error — try passcode") }
  }

  async function submitPasscode(e: React.FormEvent) {
    e.preventDefault()
    if (!passcode.trim()) return
    const res = await fetch("/api/security/reverify", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ pin: passcode }),
    })
    if (res.ok) { setStatus("success"); setMsg("Access granted"); setTimeout(onUnlocked, 800) }
    else { setPassErr(true); setPasscode(""); setTimeout(() => setPassErr(false), 2500) }
  }

  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center backdrop-blur-xl bg-background/90">
      <div className="w-full max-w-sm bg-card border border-border rounded-xl shadow-xl overflow-hidden">
        <div className="px-6 py-5 border-b border-border">
          <h2 className="text-base font-semibold text-foreground">Session locked</h2>
          <p className="text-sm text-muted-foreground mt-0.5">Your presence was not detected. Verify to continue.</p>
        </div>

        {/* Tabs */}
        <div className="flex border-b border-border">
          {(["face", "passcode"] as const).map(t => (
            <button key={t} onClick={() => setTab(t)}
              className={`flex-1 flex items-center justify-center gap-1.5 py-3 text-sm font-medium transition-colors ${
                tab === t ? "text-foreground border-b-2 border-primary -mb-px" : "text-muted-foreground hover:text-foreground"
              }`}>
              {t === "face" ? <><Scan size={14} /> Face scan</> : <><KeyRound size={14} /> Passcode</>}
            </button>
          ))}
        </div>

        <div className="p-6">
          {status === "success" ? (
            <div className="flex flex-col items-center gap-3 py-4">
              <CheckCircle2 size={40} className="text-nexus-success" />
              <p className="text-sm text-nexus-success">{msg}</p>
            </div>
          ) : tab === "face" ? (
            <div className="flex flex-col gap-4">
              {/* Live camera feed so you can see yourself while scanning */}
              <div className="relative w-full overflow-hidden rounded-lg bg-black" style={{ aspectRatio: "4/3" }}>
                <video
                  ref={videoRef}
                  className="w-full h-full object-cover"
                  style={{ transform: "scaleX(-1)" }}
                  muted
                  playsInline
                  autoPlay
                />
                {status === "scanning" && (
                  <div className="absolute inset-0 flex items-center justify-center bg-black/40">
                    <div className="flex items-center gap-2 text-sm text-white"><Loader2 size={16} className="animate-spin" /> Scanning...</div>
                  </div>
                )}
                {status === "failed" && (
                  <div className="absolute inset-0 flex items-center justify-center bg-red-950/40">
                    <XCircle size={32} className="text-nexus-danger" />
                  </div>
                )}
              </div>
              <p className={`text-sm text-center ${status === "failed" ? "text-nexus-danger" : "text-muted-foreground"}`}>{msg}</p>
              {status !== "scanning" && (
                <button onClick={scanFace}
                  className="w-full bg-primary text-primary-foreground rounded-lg py-2.5 text-sm font-medium hover:opacity-90 transition-opacity flex items-center justify-center gap-2">
                  <Scan size={15} /> {status === "failed" ? "Try again" : "Scan face"}
                </button>
              )}
            </div>
          ) : (
            <form onSubmit={submitPasscode} className="flex flex-col gap-4">
              <input type="password" value={passcode} onChange={e => setPasscode(e.target.value)}
                placeholder="Enter passcode" autoComplete="current-password"
                className={`w-full bg-background border rounded-lg px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-primary/50 font-mono tracking-wider ${passErr ? "border-nexus-danger" : "border-border"}`}
              />
              {passErr && <p className="text-xs text-nexus-danger -mt-2">Incorrect passcode</p>}
              <button type="submit" disabled={!passcode.trim()}
                className="w-full bg-primary text-primary-foreground rounded-lg py-2.5 text-sm font-medium hover:opacity-90 transition-opacity disabled:opacity-50 flex items-center justify-center gap-2">
                <KeyRound size={15} /> Unlock
              </button>
            </form>
          )}
        </div>
      </div>
    </div>
  )
}

// ── Main presence guard ──────────────────────────────────────────────────────
export default function NexusPresenceGuard({ children }: { children: React.ReactNode }) {
  const videoRef    = useRef<HTMLVideoElement>(null)
  const streamRef   = useRef<MediaStream | null>(null)
  const faceapiRef  = useRef<any>(null)
  const readyRef    = useRef(false)
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const missesRef   = useRef(0)

  const [isChecking, setIsChecking] = useState(false)
  const [isLocked,   setIsLocked]   = useState(false)

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
        const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "user", width: 320, height: 240 } })
        if (cancelled) { stream.getTracks().forEach(t => t.stop()); return }
        streamRef.current = stream
        if (videoRef.current) { videoRef.current.srcObject = stream; await videoRef.current.play() }
        readyRef.current = true
        const t = setTimeout(() => {
          if (cancelled || !readyRef.current) return
          runCheck()
          intervalRef.current = setInterval(() => { if (readyRef.current) runCheck() }, CHECK_INTERVAL_MS)
        }, FIRST_CHECK_DELAY_MS)
        return () => clearTimeout(t)
      } catch { /* camera unavailable — silent */ }
    }
    init()
    return () => {
      cancelled = true; readyRef.current = false
      if (intervalRef.current) clearInterval(intervalRef.current)
      streamRef.current?.getTracks().forEach(t => t.stop())
    }
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  async function runCheck() {
    if (!readyRef.current || !faceapiRef.current || !videoRef.current) return
    setIsChecking(true)
    try {
      const opts = new faceapiRef.current.TinyFaceDetectorOptions({ inputSize: 160, scoreThreshold: 0.4 })
      const result = await faceapiRef.current.detectSingleFace(videoRef.current, opts).withFaceLandmarks(true).withFaceDescriptor()
      if (!result) {
        missesRef.current += 1
        if (missesRef.current >= MAX_MISSES) setIsLocked(true)
      } else {
        missesRef.current = 0
        setIsLocked(false)
      }
    } catch { /* skip */ } finally { setIsChecking(false) }
  }

  return (
    <>
      <video ref={videoRef} className="hidden" muted playsInline />

      {/* Subtle presence indicator */}
      <div className="fixed top-3 right-4 z-50 flex items-center gap-1.5 pointer-events-none">
        <div className={`w-1.5 h-1.5 rounded-full transition-colors ${isChecking ? "bg-nexus-warning animate-pulse" : "bg-nexus-success/50"}`} />
      </div>

      {isLocked && (
        <LockScreen videoRef={videoRef} faceapiRef={faceapiRef}
          onUnlocked={() => { missesRef.current = 0; setIsLocked(false) }} />
      )}
      {children}
    </>
  )
}
