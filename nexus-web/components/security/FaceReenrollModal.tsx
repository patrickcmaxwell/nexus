"use client"

// Multi-frame face re-enrollment modal. Five guided prompts; auto-captures
// each angle when a face is detected, then POSTs the descriptor array to
// /api/security/face. Used from /dashboard/settings.
//
// Mirrors the capture loop in /invite/[token]/page.tsx but stripped of
// avatar/onboarding concerns — re-enrollment only writes face data.

import { useEffect, useRef, useState } from "react"
import { Loader2, Scan, CheckCircle2, X } from "lucide-react"

const FACE_PROMPTS = [
  { key: "front",  label: "Look forward",       tip: "Center your face" },
  { key: "left",   label: "Slowly look left",   tip: "Just turn your head" },
  { key: "right",  label: "Now look right",     tip: "Same — small turn" },
  { key: "up",     label: "Tip your chin up",   tip: "Eyes on the camera" },
  { key: "smile",  label: "Smile back",         tip: "Capture expression" },
]

type Stage = "loading" | "capturing" | "uploading" | "done" | "error" | "no_camera"

export default function FaceReenrollModal({
  open,
  onClose,
  onSuccess,
}: {
  open: boolean
  onClose: () => void
  onSuccess?: (framesStored: number) => void
}) {
  const [stage, setStage] = useState<Stage>("loading")
  const [statusMsg, setStatusMsg] = useState("")
  const [promptIdx, setPromptIdx] = useState(0)
  const [captured, setCaptured] = useState<number[][]>([])
  const [faceDetected, setFaceDetected] = useState(false)
  const [justCaptured, setJustCaptured] = useState(false)

  const videoRef = useRef<HTMLVideoElement>(null)
  const streamRef = useRef<MediaStream | null>(null)
  const faceapiRef = useRef<any>(null)
  const captureLoopRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const cooldownRef = useRef(false)

  // Reset state every time the modal opens
  useEffect(() => {
    if (!open) return
    setStage("loading")
    setStatusMsg("Starting camera...")
    setPromptIdx(0)
    setCaptured([])
    setFaceDetected(false)
    setJustCaptured(false)
    cooldownRef.current = false
  }, [open])

  // Camera + model setup
  useEffect(() => {
    if (!open || stage !== "loading") return
    let cancelled = false

    ;(async () => {
      try {
        const stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: "user", width: { ideal: 640 }, height: { ideal: 480 } },
        })
        if (cancelled) {
          stream.getTracks().forEach((t) => t.stop())
          return
        }
        streamRef.current = stream
        await new Promise((r) => setTimeout(r, 50))
        if (videoRef.current) {
          videoRef.current.srcObject = stream
          await new Promise<void>((resolve) => {
            if (!videoRef.current) return resolve()
            videoRef.current.onloadedmetadata = () => {
              videoRef.current?.play().catch(() => {})
              resolve()
            }
          })
        }
        setStatusMsg("Loading face recognition...")
        const faceapi = await import("@vladmandic/face-api")
        const MODEL_URL = "https://cdn.jsdelivr.net/npm/@vladmandic/face-api/model"
        await Promise.all([
          faceapi.nets.tinyFaceDetector.loadFromUri(MODEL_URL),
          faceapi.nets.faceLandmark68TinyNet.loadFromUri(MODEL_URL),
          faceapi.nets.faceRecognitionNet.loadFromUri(MODEL_URL),
        ])
        if (cancelled) return
        faceapiRef.current = faceapi
        setStage("capturing")
        setStatusMsg("")
      } catch {
        if (!cancelled) {
          setStage("no_camera")
          setStatusMsg("Camera unavailable")
        }
      }
    })()

    return () => { cancelled = true }
  }, [open, stage])

  // Capture loop
  useEffect(() => {
    if (stage !== "capturing") return

    const tick = async () => {
      if (cooldownRef.current) return
      const faceapi = faceapiRef.current
      const video = videoRef.current
      if (!faceapi || !video) return

      const options = new faceapi.TinyFaceDetectorOptions({ inputSize: 320, scoreThreshold: 0.5 })
      const result = await faceapi
        .detectSingleFace(video, options)
        .withFaceLandmarks(true)
        .withFaceDescriptor()

      if (!result) {
        setFaceDetected(false)
        return
      }
      setFaceDetected(true)

      const descriptor = Array.from(result.descriptor) as number[]
      cooldownRef.current = true
      setCaptured((prev) => [...prev, descriptor])
      setJustCaptured(true)
      setTimeout(() => setJustCaptured(false), 600)
      setTimeout(() => {
        cooldownRef.current = false
        setPromptIdx((idx) => {
          const next = idx + 1
          if (next >= FACE_PROMPTS.length) {
            if (captureLoopRef.current) clearInterval(captureLoopRef.current)
            captureLoopRef.current = null
            streamRef.current?.getTracks().forEach((t) => t.stop())
            streamRef.current = null
            setTimeout(() => upload(), 400)
          }
          return next
        })
      }, 1100)
    }

    captureLoopRef.current = setInterval(tick, 600)
    return () => {
      if (captureLoopRef.current) clearInterval(captureLoopRef.current)
      captureLoopRef.current = null
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [stage])

  // Cleanup on unmount or close
  useEffect(() => {
    return () => {
      if (captureLoopRef.current) clearInterval(captureLoopRef.current)
      streamRef.current?.getTracks().forEach((t) => t.stop())
    }
  }, [])

  // Closing the modal mid-capture should release the camera
  useEffect(() => {
    if (open) return
    if (captureLoopRef.current) clearInterval(captureLoopRef.current)
    captureLoopRef.current = null
    streamRef.current?.getTracks().forEach((t) => t.stop())
    streamRef.current = null
  }, [open])

  async function upload() {
    setStage("uploading")
    setStatusMsg("Saving frames...")
    try {
      // Read latest captured array via state setter to avoid closure staleness
      let frames: number[][] = []
      setCaptured((prev) => { frames = prev; return prev })
      // Tiny defer so the setCaptured read above resolves
      await new Promise((r) => setTimeout(r, 0))

      const res = await fetch("/api/security/face", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "enroll", descriptors: frames }),
      })
      if (!res.ok) {
        const data = await res.json().catch(() => ({}))
        setStage("error")
        setStatusMsg(data.error || "Save failed")
        return
      }
      const data = await res.json()
      setStage("done")
      onSuccess?.(data.framesStored ?? frames.length)
      setTimeout(onClose, 1200)
    } catch {
      setStage("error")
      setStatusMsg("Network error")
    }
  }

  if (!open) return null

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-sm p-4">
      <div
        className="relative w-full max-w-md overflow-hidden"
        style={{
          background: "oklch(0.10 0.015 240)",
          border: "1px solid oklch(0.75 0.18 200 / 0.3)",
          boxShadow: "0 0 50px oklch(0.75 0.18 200 / 0.15)",
        }}
      >
        <div className="absolute top-0 left-0 w-4 h-4 border-t-2 border-l-2 border-[var(--nexus-cyan)]/60" />
        <div className="absolute top-0 right-0 w-4 h-4 border-t-2 border-r-2 border-[var(--nexus-cyan)]/60" />
        <div className="absolute bottom-0 left-0 w-4 h-4 border-b-2 border-l-2 border-[var(--nexus-cyan)]/60" />
        <div className="absolute bottom-0 right-0 w-4 h-4 border-b-2 border-r-2 border-[var(--nexus-cyan)]/60" />

        <button
          type="button"
          onClick={onClose}
          className="absolute top-3 right-3 z-10 text-muted-foreground/60 hover:text-foreground transition-colors"
          aria-label="Close"
        >
          <X size={18} />
        </button>

        <div className="p-6">
          <div className="flex items-center gap-3 mb-4">
            <div
              className="w-10 h-10 rounded-full flex items-center justify-center"
              style={{ background: "oklch(0.75 0.18 200 / 0.1)", border: "1px solid oklch(0.75 0.18 200 / 0.3)", color: "var(--nexus-cyan)" }}
            >
              <Scan size={18} />
            </div>
            <div>
              <p className="text-sm font-semibold text-foreground">Re-enroll your face</p>
              <p className="text-xs text-muted-foreground">Five quick angles — replaces previous frames</p>
            </div>
          </div>

          <div className="relative overflow-hidden bg-black mb-3" style={{ aspectRatio: "4/3", border: "1px solid oklch(0.75 0.18 200 / 0.2)" }}>
            <video ref={videoRef} className="w-full h-full object-cover" style={{ transform: "scaleX(-1)" }} muted playsInline autoPlay />

            {(stage === "loading" || stage === "uploading") && (
              <div className="absolute inset-0 bg-black/70 flex flex-col items-center justify-center gap-3 z-20">
                <Loader2 size={20} className="animate-spin" style={{ color: "var(--nexus-cyan)" }} />
                <span className="font-mono text-[9px] text-muted-foreground/80 tracking-widest uppercase">{statusMsg}</span>
              </div>
            )}

            {stage === "capturing" && faceDetected && (
              <div className="absolute top-3 right-3 z-20 flex items-center gap-1.5 px-2 py-1 bg-emerald-500/15 border border-emerald-400/40">
                <div className="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse" />
                <span className="font-mono text-[9px] tracking-widest text-emerald-300 uppercase">Face Lock</span>
              </div>
            )}

            {justCaptured && (
              <div className="absolute inset-0 z-30 flex items-center justify-center pointer-events-none" style={{ background: "oklch(0.65 0.18 155 / 0.2)" }}>
                <CheckCircle2 size={64} style={{ color: "var(--nexus-success)" }} />
              </div>
            )}

            {stage === "done" && (
              <div className="absolute inset-0 z-30 flex flex-col items-center justify-center gap-3" style={{ background: "oklch(0.65 0.18 155 / 0.25)" }}>
                <CheckCircle2 size={48} style={{ color: "var(--nexus-success)" }} />
                <span className="font-mono text-[10px] tracking-widest text-emerald-300 uppercase">Enrolled</span>
              </div>
            )}
          </div>

          <div className="flex items-center justify-center gap-1.5 mb-3">
            {FACE_PROMPTS.map((p, i) => (
              <div
                key={p.key}
                className="w-2 h-2 rounded-full transition-all"
                style={{
                  background: i < captured.length
                    ? "var(--nexus-success)"
                    : i === promptIdx ? "var(--nexus-cyan)" : "oklch(0.75 0.18 200 / 0.15)",
                  transform: i === promptIdx && stage === "capturing" ? "scale(1.4)" : "scale(1)",
                }}
              />
            ))}
          </div>

          <div className="text-center min-h-[44px]">
            {stage === "capturing" && promptIdx < FACE_PROMPTS.length && (
              <>
                <p className="text-sm font-semibold text-foreground">{FACE_PROMPTS[promptIdx].label}</p>
                <p className="text-xs text-muted-foreground mt-0.5">{FACE_PROMPTS[promptIdx].tip}</p>
              </>
            )}
            {stage === "no_camera" && (
              <p className="text-xs text-destructive">Camera unavailable. Close and try again.</p>
            )}
            {stage === "error" && (
              <p className="text-xs text-destructive">{statusMsg}</p>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}
