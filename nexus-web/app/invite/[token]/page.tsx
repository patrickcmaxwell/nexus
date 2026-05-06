"use client"

import { useState, useEffect, useRef, useCallback } from "react"
import { useParams } from "next/navigation"
import { Scan, KeyRound, Loader2, CheckCircle2, Shield, Lock, Camera, Upload, ArrowRight, SkipForward, Sparkles } from "lucide-react"

type Stage =
  | "loading"
  | "invalid"
  | "used"
  | "welcome"
  | "setup_pin"
  | "setup_face"
  | "choose_avatar"
  | "directives"
  | "enrolling"
  | "success"

// Five framing prompts. Each one captures a face_descriptor under a different
// angle/expression so the verify path has multiple references to compare against
// — dramatically improves recognition under varied lighting & angle on later logins.
const FACE_PROMPTS: { key: string; label: string; tip: string }[] = [
  { key: "front",  label: "Look forward",       tip: "Center your face in the frame" },
  { key: "left",   label: "Slowly look left",   tip: "Turn just your head, not your shoulders" },
  { key: "right",  label: "Now look right",     tip: "Same — small turn is enough" },
  { key: "up",     label: "Tip your chin up",   tip: "Just a little, eyes on the camera" },
  { key: "smile",  label: "Smile back at us",   tip: "We capture expression too" },
]

const DIRECTIVE_QUESTIONS: { key: string; title: string; placeholder: string }[] = [
  {
    key: "address",
    title: "How should Eve address you?",
    placeholder: "e.g. \"Just call me by my first name\" — or \"Always sir / madam\"",
  },
  {
    key: "remember",
    title: "What's one thing Eve should always remember about you?",
    placeholder: "e.g. \"I'm a night owl, schedule things after 2pm\" — or your role, your kids' names, anything",
  },
  {
    key: "offlimits",
    title: "What's off-limits?",
    placeholder: "e.g. \"Never schedule before 7am\" — or topics, contacts, hours",
  },
]

export default function InvitePage() {
  const params = useParams()
  const token = params.token as string

  const [stage, setStage] = useState<Stage>("loading")
  const [name, setName] = useState("")
  const [pin, setPin] = useState("")
  const [pinConfirm, setPinConfirm] = useState("")
  const [pinError, setPinError] = useState("")
  const [statusMsg, setStatusMsg] = useState("")

  // Face capture state
  const videoRef = useRef<HTMLVideoElement>(null)
  const streamRef = useRef<MediaStream | null>(null)
  const faceapiRef = useRef<any>(null)
  const captureLoopRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const [cameraReady, setCameraReady] = useState(false)
  const [promptIdx, setPromptIdx] = useState(0)
  const [capturedDescriptors, setCapturedDescriptors] = useState<number[][]>([])
  const [faceDetected, setFaceDetected] = useState(false)
  const [justCaptured, setJustCaptured] = useState(false)
  const captureCooldownRef = useRef<boolean>(false)

  // Avatar (data URL — uploaded server-side during /api/team/setup)
  const [avatarPreview, setAvatarPreview] = useState<string | null>(null)
  const [avatarChoice, setAvatarChoice] = useState<"capture" | "upload" | "skip">("capture")

  // Directives
  const [directiveAnswers, setDirectiveAnswers] = useState<Record<string, string>>({})

  // ── Validate the invite token on mount ───────────────────────────────────
  useEffect(() => {
    fetch(`/api/team/setup?token=${token}`)
      .then(async (r) => {
        if (r.ok) {
          const data = await r.json()
          setName(data.displayName)
          setStage("welcome")
        } else if (r.status === 410) {
          setStage("used")
        } else {
          setStage("invalid")
        }
      })
      .catch(() => setStage("invalid"))
  }, [token])

  // ── Cleanup camera on unmount or stage change away from face ─────────────
  useEffect(() => {
    return () => {
      if (captureLoopRef.current) clearInterval(captureLoopRef.current)
      streamRef.current?.getTracks().forEach((t) => t.stop())
    }
  }, [])

  // ── Face capture: start camera + load models when entering setup_face ────
  useEffect(() => {
    if (stage !== "setup_face") return
    let cancelled = false

    ;(async () => {
      setCameraReady(false)
      setStatusMsg("Starting camera...")
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
        setCameraReady(true)
        setStatusMsg("")
      } catch {
        if (!cancelled) {
          setStatusMsg("Camera unavailable — you can skip face enrollment")
          setCameraReady(false)
        }
      }
    })()

    return () => {
      cancelled = true
    }
  }, [stage])

  // ── Continuous capture loop ──────────────────────────────────────────────
  useEffect(() => {
    if (stage !== "setup_face" || !cameraReady) return

    const tick = async () => {
      if (captureCooldownRef.current) return
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

      // Capture this frame for the current prompt and advance
      const descriptor = Array.from(result.descriptor) as number[]
      captureCooldownRef.current = true
      setCapturedDescriptors((prev) => {
        const next = [...prev, descriptor]
        // Snapshot the very first frame as the default avatar
        if (prev.length === 0 && videoRef.current) {
          const c = document.createElement("canvas")
          c.width = videoRef.current.videoWidth || 480
          c.height = videoRef.current.videoHeight || 480
          const ctx = c.getContext("2d")
          if (ctx) {
            // Mirror to match the on-screen video
            ctx.translate(c.width, 0)
            ctx.scale(-1, 1)
            ctx.drawImage(videoRef.current, 0, 0, c.width, c.height)
            // Square crop centered
            const side = Math.min(c.width, c.height)
            const sq = document.createElement("canvas")
            sq.width = sq.height = side
            const sctx = sq.getContext("2d")
            sctx?.drawImage(c, (c.width - side) / 2, (c.height - side) / 2, side, side, 0, 0, side, side)
            setAvatarPreview(sq.toDataURL("image/jpeg", 0.85))
          }
        }
        return next
      })
      setJustCaptured(true)
      setTimeout(() => setJustCaptured(false), 600)
      setTimeout(() => {
        captureCooldownRef.current = false
        setPromptIdx((idx) => {
          const next = idx + 1
          if (next >= FACE_PROMPTS.length) {
            // Done — stop capture loop, advance to avatar selection
            if (captureLoopRef.current) clearInterval(captureLoopRef.current)
            captureLoopRef.current = null
            streamRef.current?.getTracks().forEach((t) => t.stop())
            streamRef.current = null
            setTimeout(() => setStage("choose_avatar"), 400)
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
  }, [stage, cameraReady])

  // ── Stage handlers ───────────────────────────────────────────────────────
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

  function skipFaceEnrollment() {
    if (captureLoopRef.current) clearInterval(captureLoopRef.current)
    streamRef.current?.getTracks().forEach((t) => t.stop())
    streamRef.current = null
    setStage("choose_avatar")
  }

  const handleAvatarUpload = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return
    if (!file.type.startsWith("image/")) return
    const reader = new FileReader()
    reader.onload = () => {
      const result = reader.result as string
      setAvatarPreview(result)
      setAvatarChoice("upload")
    }
    reader.readAsDataURL(file)
  }, [])

  async function completeSetup() {
    setStage("enrolling")
    setStatusMsg("Setting up your account...")

    const directivesPayload = DIRECTIVE_QUESTIONS
      .map((q) => ({ title: q.title, content: (directiveAnswers[q.key] ?? "").trim() }))
      .filter((d) => d.content.length > 0)

    try {
      const res = await fetch("/api/team/setup", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          token,
          pin,
          faceDescriptors: capturedDescriptors,
          avatarDataUrl: avatarChoice !== "skip" ? avatarPreview : null,
          directives: directivesPayload,
        }),
      })

      if (res.ok) {
        setStage("success")
        setStatusMsg("Welcome to Nexus!")
        setTimeout(() => window.location.replace("/dashboard"), 1500)
      } else {
        const data = await res.json().catch(() => ({}))
        setStage("setup_pin")
        setPinError(data.error || "Setup failed — try again")
      }
    } catch {
      setStage("setup_pin")
      setPinError("Network error — try again")
    }
  }

  // ── Render ───────────────────────────────────────────────────────────────
  if (stage === "loading") {
    return (
      <Centered>
        <Loader2 size={24} className="animate-spin mx-auto mb-4" style={{ color: "var(--nexus-cyan)" }} />
        <p className="font-mono text-xs tracking-widest text-muted-foreground uppercase">Verifying invite...</p>
      </Centered>
    )
  }

  if (stage === "invalid") {
    return (
      <Centered>
        <Shield size={48} className="mx-auto mb-6 text-destructive" />
        <h1 className="text-xl font-bold text-foreground mb-2">Invalid Invite</h1>
        <p className="text-sm text-muted-foreground">This invite link is invalid or has expired. Contact the Director for a new one.</p>
      </Centered>
    )
  }

  if (stage === "used") {
    return (
      <Centered>
        <CheckCircle2 size={48} className="mx-auto mb-6" style={{ color: "var(--nexus-success)" }} />
        <h1 className="text-xl font-bold text-foreground mb-2">Already Activated</h1>
        <p className="text-sm text-muted-foreground mb-6">This invite has already been used. You can log in normally.</p>
        <a href="/" className="font-mono text-xs tracking-widest uppercase" style={{ color: "var(--nexus-cyan)" }}>
          Go to login →
        </a>
      </Centered>
    )
  }

  if (stage === "success") {
    return (
      <Centered>
        <CheckCircle2 size={48} className="mx-auto mb-6" style={{ color: "var(--nexus-success)" }} />
        <h1 className="text-2xl font-bold text-foreground mb-2">Welcome, {name}</h1>
        <p className="font-mono text-xs tracking-widest text-muted-foreground uppercase animate-pulse">Entering Nexus...</p>
      </Centered>
    )
  }

  // Wizard layout — header + progress dots + content card
  const stageOrder: Stage[] = ["welcome", "setup_pin", "setup_face", "choose_avatar", "directives"]
  const stepIdx = stageOrder.indexOf(stage)
  const totalSteps = stageOrder.length

  return (
    <div className="min-h-screen bg-background nexus-grid-bg flex flex-col items-center justify-center p-6 relative">
      <div
        className="absolute inset-0 pointer-events-none"
        style={{ background: "radial-gradient(ellipse 50% 40% at 50% 50%, oklch(0.75 0.18 200 / 0.05) 0%, transparent 70%)" }}
      />

      <div className="relative z-10 mb-6 text-center">
        <p className="font-mono text-[10px] tracking-[0.3em] uppercase mb-1" style={{ color: "var(--nexus-cyan)" }}>Nexus</p>
        <h1 className="text-2xl font-bold text-foreground mb-3">Welcome, {name}</h1>
        <div className="flex items-center justify-center gap-2">
          {Array.from({ length: totalSteps }).map((_, i) => (
            <div
              key={i}
              className="h-1 w-8 transition-all"
              style={{
                background: i <= stepIdx ? "var(--nexus-cyan)" : "oklch(0.75 0.18 200 / 0.18)",
                boxShadow: i === stepIdx ? "0 0 8px oklch(0.75 0.18 200 / 0.6)" : "none",
              }}
            />
          ))}
        </div>
        <p className="font-mono text-[9px] tracking-widest text-muted-foreground/60 uppercase mt-3">
          Step {stepIdx + 1} of {totalSteps} — {stageLabel(stage)}
        </p>
      </div>

      <div
        className="relative z-10 w-full max-w-md overflow-hidden"
        style={{
          background: "oklch(0.10 0.015 240)",
          border: "1px solid oklch(0.75 0.18 200 / 0.25)",
          boxShadow: "0 0 40px oklch(0.75 0.18 200 / 0.08)",
        }}
      >
        <div className="absolute top-0 left-0 w-4 h-4 border-t-2 border-l-2 border-[var(--nexus-cyan)]/60" />
        <div className="absolute top-0 right-0 w-4 h-4 border-t-2 border-r-2 border-[var(--nexus-cyan)]/60" />
        <div className="absolute bottom-0 left-0 w-4 h-4 border-b-2 border-l-2 border-[var(--nexus-cyan)]/60" />
        <div className="absolute bottom-0 right-0 w-4 h-4 border-b-2 border-r-2 border-[var(--nexus-cyan)]/60" />

        <div className="p-6">
          {stage === "welcome" && (
            <div className="flex flex-col gap-5 items-center text-center">
              <Sparkles size={40} style={{ color: "var(--nexus-cyan)" }} />
              <p className="text-sm text-foreground">
                You've been invited into Nexus — a private command center.
              </p>
              <p className="text-xs text-muted-foreground leading-relaxed">
                We'll set up a PIN, capture your face for quick logins, pick an avatar, and ask three short questions so Eve can be useful from minute one.
              </p>
              <p className="text-xs text-muted-foreground/60">Takes about 90 seconds.</p>
              <button
                type="button"
                onClick={() => setStage("setup_pin")}
                className="w-full py-3 mt-2 font-mono text-[10px] tracking-[0.2em] uppercase flex items-center justify-center gap-2 transition-all"
                style={{ background: "oklch(0.75 0.18 200 / 0.12)", border: "1px solid oklch(0.75 0.18 200 / 0.5)", color: "var(--nexus-cyan)" }}
              >
                Begin <ArrowRight size={13} />
              </button>
            </div>
          )}

          {stage === "setup_pin" && (
            <form onSubmit={handlePinSubmit} className="flex flex-col gap-4">
              <div className="flex items-center gap-3 mb-1">
                <IconBubble><Lock size={18} /></IconBubble>
                <div>
                  <p className="text-sm font-semibold text-foreground">Choose your PIN</p>
                  <p className="text-xs text-muted-foreground">4–8 digits. You'll use this every login.</p>
                </div>
              </div>

              <PinInput value={pin} onChange={setPin} placeholder="••••" autoFocus error={!!pinError} label="PIN" />
              <PinInput value={pinConfirm} onChange={setPinConfirm} placeholder="••••" error={!!pinError} label="Confirm" />

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
                <KeyRound size={13} /> Continue
              </button>
            </form>
          )}

          {stage === "setup_face" && (
            <div className="flex flex-col gap-4">
              <div className="flex items-center gap-3 mb-1">
                <IconBubble><Scan size={18} /></IconBubble>
                <div>
                  <p className="text-sm font-semibold text-foreground">Face enrollment</p>
                  <p className="text-xs text-muted-foreground">Five quick angles for reliable recognition</p>
                </div>
              </div>

              <div className="relative overflow-hidden bg-black" style={{ aspectRatio: "4/3", border: "1px solid oklch(0.75 0.18 200 / 0.2)" }}>
                <div className="absolute top-2 left-2 w-5 h-5 border-t-2 border-l-2 border-[var(--nexus-cyan)]/70 z-10" />
                <div className="absolute top-2 right-2 w-5 h-5 border-t-2 border-r-2 border-[var(--nexus-cyan)]/70 z-10" />
                <div className="absolute bottom-2 left-2 w-5 h-5 border-b-2 border-l-2 border-[var(--nexus-cyan)]/70 z-10" />
                <div className="absolute bottom-2 right-2 w-5 h-5 border-b-2 border-r-2 border-[var(--nexus-cyan)]/70 z-10" />
                <video ref={videoRef} className="w-full h-full object-cover" style={{ transform: "scaleX(-1)" }} muted playsInline autoPlay />

                {!cameraReady && statusMsg && (
                  <div className="absolute inset-0 bg-black/70 flex flex-col items-center justify-center gap-3 z-20">
                    <Loader2 size={20} className="animate-spin" style={{ color: "var(--nexus-cyan)" }} />
                    <span className="font-mono text-[9px] text-muted-foreground/80 tracking-widest uppercase">{statusMsg}</span>
                  </div>
                )}

                {cameraReady && (
                  <>
                    {faceDetected && (
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
                  </>
                )}
              </div>

              <div className="flex items-center justify-center gap-1.5">
                {FACE_PROMPTS.map((p, i) => (
                  <div
                    key={p.key}
                    className="w-2 h-2 rounded-full transition-all"
                    style={{
                      background: i < capturedDescriptors.length
                        ? "var(--nexus-success)"
                        : i === promptIdx ? "var(--nexus-cyan)" : "oklch(0.75 0.18 200 / 0.15)",
                      transform: i === promptIdx && cameraReady ? "scale(1.4)" : "scale(1)",
                    }}
                  />
                ))}
              </div>

              <div className="text-center min-h-[44px]">
                {cameraReady && promptIdx < FACE_PROMPTS.length ? (
                  <>
                    <p className="text-sm font-semibold text-foreground">{FACE_PROMPTS[promptIdx].label}</p>
                    <p className="text-xs text-muted-foreground mt-0.5">{FACE_PROMPTS[promptIdx].tip}</p>
                  </>
                ) : !cameraReady ? (
                  <p className="text-xs text-muted-foreground">{statusMsg || "Loading..."}</p>
                ) : (
                  <p className="text-sm font-semibold text-emerald-400">All angles captured!</p>
                )}
              </div>

              <button
                type="button"
                onClick={skipFaceEnrollment}
                className="w-full py-2 font-mono text-[9px] tracking-[0.15em] uppercase text-muted-foreground/50 hover:text-muted-foreground transition-colors"
              >
                Skip face enrollment — use PIN only
              </button>
            </div>
          )}

          {stage === "choose_avatar" && (
            <div className="flex flex-col gap-4">
              <div className="flex items-center gap-3 mb-1">
                <IconBubble><Camera size={18} /></IconBubble>
                <div>
                  <p className="text-sm font-semibold text-foreground">Pick your avatar</p>
                  <p className="text-xs text-muted-foreground">Shows up across the dashboard and team picker</p>
                </div>
              </div>

              <div className="flex items-center justify-center">
                {avatarPreview ? (
                  <div
                    className="w-32 h-32 rounded-full overflow-hidden border-2"
                    style={{ borderColor: avatarChoice !== "skip" ? "var(--nexus-cyan)" : "var(--border)" }}
                  >
                    <img src={avatarPreview} alt="avatar preview" className="w-full h-full object-cover" />
                  </div>
                ) : (
                  <div
                    className="w-32 h-32 rounded-full flex items-center justify-center text-3xl font-bold"
                    style={{ background: "oklch(0.75 0.18 200 / 0.1)", border: "2px solid oklch(0.75 0.18 200 / 0.3)", color: "var(--nexus-cyan)" }}
                  >
                    {(name || "?").split(" ").map((s) => s[0]).join("").slice(0, 2).toUpperCase()}
                  </div>
                )}
              </div>

              <div className="flex flex-col gap-2 mt-2">
                {avatarPreview && (
                  <button
                    type="button"
                    onClick={() => setAvatarChoice("capture")}
                    className="w-full py-2.5 font-mono text-[10px] tracking-[0.15em] uppercase flex items-center justify-center gap-2 transition-all"
                    style={{
                      background: avatarChoice === "capture" ? "oklch(0.75 0.18 200 / 0.18)" : "transparent",
                      border: `1px solid ${avatarChoice === "capture" ? "oklch(0.75 0.18 200 / 0.6)" : "oklch(0.75 0.18 200 / 0.25)"}`,
                      color: avatarChoice === "capture" ? "var(--nexus-cyan)" : "var(--muted-foreground)",
                    }}
                  >
                    <CheckCircle2 size={13} /> Use captured frame
                  </button>
                )}
                <label
                  className="w-full py-2.5 font-mono text-[10px] tracking-[0.15em] uppercase flex items-center justify-center gap-2 transition-all cursor-pointer"
                  style={{
                    background: avatarChoice === "upload" ? "oklch(0.75 0.18 200 / 0.18)" : "transparent",
                    border: `1px solid ${avatarChoice === "upload" ? "oklch(0.75 0.18 200 / 0.6)" : "oklch(0.75 0.18 200 / 0.25)"}`,
                    color: avatarChoice === "upload" ? "var(--nexus-cyan)" : "var(--muted-foreground)",
                  }}
                >
                  <Upload size={13} /> Upload an image
                  <input type="file" accept="image/png,image/jpeg,image/webp" className="hidden" onChange={handleAvatarUpload} />
                </label>
                <button
                  type="button"
                  onClick={() => { setAvatarChoice("skip"); setAvatarPreview(null) }}
                  className="w-full py-2 font-mono text-[9px] tracking-[0.15em] uppercase text-muted-foreground/50 hover:text-muted-foreground transition-colors"
                >
                  Skip — use initials
                </button>
              </div>

              <button
                type="button"
                onClick={() => setStage("directives")}
                className="w-full py-3 mt-2 font-mono text-[10px] tracking-[0.2em] uppercase flex items-center justify-center gap-2 transition-all"
                style={{ background: "oklch(0.75 0.18 200 / 0.12)", border: "1px solid oklch(0.75 0.18 200 / 0.5)", color: "var(--nexus-cyan)" }}
              >
                Continue <ArrowRight size={13} />
              </button>
            </div>
          )}

          {stage === "directives" && (
            <div className="flex flex-col gap-4">
              <div className="flex items-center gap-3 mb-1">
                <IconBubble><Sparkles size={18} /></IconBubble>
                <div>
                  <p className="text-sm font-semibold text-foreground">Tell Eve about you</p>
                  <p className="text-xs text-muted-foreground">All optional, all editable later</p>
                </div>
              </div>

              {DIRECTIVE_QUESTIONS.map((q) => (
                <div key={q.key} className="flex flex-col gap-1.5">
                  <label className="font-mono text-[9px] tracking-[0.15em] text-muted-foreground uppercase">{q.title}</label>
                  <textarea
                    value={directiveAnswers[q.key] ?? ""}
                    onChange={(e) => setDirectiveAnswers((prev) => ({ ...prev, [q.key]: e.target.value }))}
                    placeholder={q.placeholder}
                    rows={2}
                    maxLength={500}
                    className="w-full px-3 py-2 font-sans text-sm placeholder:text-muted-foreground/40 focus:outline-none transition-all resize-none"
                    style={{
                      background: "oklch(0.08 0.01 240)",
                      border: "1px solid oklch(0.75 0.18 200 / 0.25)",
                      color: "var(--foreground)",
                    }}
                    onFocus={(e) => { e.currentTarget.style.borderColor = "oklch(0.75 0.18 200 / 0.6)" }}
                    onBlur={(e) => { e.currentTarget.style.borderColor = "oklch(0.75 0.18 200 / 0.25)" }}
                  />
                </div>
              ))}

              <div className="flex flex-col gap-2 mt-2">
                <button
                  type="button"
                  onClick={completeSetup}
                  className="w-full py-3 font-mono text-[10px] tracking-[0.2em] uppercase flex items-center justify-center gap-2 transition-all"
                  style={{ background: "oklch(0.65 0.18 155 / 0.15)", border: "1px solid oklch(0.65 0.18 155 / 0.5)", color: "var(--nexus-success)" }}
                >
                  <CheckCircle2 size={13} /> Complete setup
                </button>
                <button
                  type="button"
                  onClick={() => { setDirectiveAnswers({}); completeSetup() }}
                  className="w-full py-2 font-mono text-[9px] tracking-[0.15em] uppercase text-muted-foreground/50 hover:text-muted-foreground transition-colors flex items-center justify-center gap-1.5"
                >
                  <SkipForward size={11} /> Skip and finish
                </button>
              </div>
            </div>
          )}

          {stage === "enrolling" && (
            <div className="flex flex-col items-center gap-4 py-8">
              <Loader2 size={24} className="animate-spin" style={{ color: "var(--nexus-cyan)" }} />
              <p className="font-mono text-[10px] tracking-widest text-muted-foreground uppercase">{statusMsg || "Setting up..."}</p>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

function stageLabel(s: Stage): string {
  switch (s) {
    case "welcome": return "Welcome"
    case "setup_pin": return "PIN"
    case "setup_face": return "Face"
    case "choose_avatar": return "Avatar"
    case "directives": return "Directives"
    default: return ""
  }
}

function Centered({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-screen bg-background flex items-center justify-center">
      <div className="text-center max-w-sm">{children}</div>
    </div>
  )
}

function IconBubble({ children }: { children: React.ReactNode }) {
  return (
    <div
      className="w-10 h-10 rounded-full flex items-center justify-center shrink-0"
      style={{ background: "oklch(0.75 0.18 200 / 0.1)", border: "1px solid oklch(0.75 0.18 200 / 0.3)", color: "var(--nexus-cyan)" }}
    >
      {children}
    </div>
  )
}

function PinInput({
  value, onChange, placeholder, autoFocus, error, label,
}: {
  value: string; onChange: (v: string) => void; placeholder: string;
  autoFocus?: boolean; error?: boolean; label: string
}) {
  return (
    <div>
      <label className="block font-mono text-[9px] tracking-[0.2em] text-muted-foreground uppercase mb-2">{label}</label>
      <input
        type="password"
        inputMode="numeric"
        pattern="[0-9]*"
        value={value}
        onChange={(e) => onChange(e.target.value.replace(/\D/g, ""))}
        placeholder={placeholder}
        autoFocus={autoFocus}
        maxLength={8}
        className="w-full px-4 py-3 font-mono text-lg tracking-[0.5em] text-center placeholder:text-muted-foreground/30 focus:outline-none transition-all"
        style={{
          background: "oklch(0.08 0.01 240)",
          border: error ? "1px solid var(--nexus-danger)" : "1px solid oklch(0.75 0.18 200 / 0.25)",
          color: "var(--foreground)",
        }}
      />
    </div>
  )
}
