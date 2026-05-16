"use client"

// Self-service face photo upload. The user picks a still image from disk,
// the browser extracts a 128-dim descriptor via face-api, and POSTs it to
// /api/security/face (action: enroll). Complementary to FaceReenrollModal —
// that one captures from the webcam; this one accepts a chosen photo for
// folks without a camera, or who'd rather use a known-good headshot.
//
// Optionally sets the same image as the user's avatar in one step.

import { useRef, useState } from "react"
import { Loader2, CheckCircle2, X, Upload, RefreshCw, ImagePlus } from "lucide-react"

type Stage = "idle" | "processing" | "ready" | "saving" | "done" | "error"

export default function FacePhotoUploadModal({
  open,
  onClose,
  onSuccess,
}: {
  open: boolean
  onClose: () => void
  onSuccess?: (opts: { framesTotal: number; avatarUpdated: boolean }) => void
}) {
  const fileInputRef = useRef<HTMLInputElement>(null)
  const faceapiRef = useRef<any>(null)

  const [stage, setStage] = useState<Stage>("idle")
  const [statusMsg, setStatusMsg] = useState("")
  const [photoUrl, setPhotoUrl] = useState<string | null>(null)
  const [photoDataUrl, setPhotoDataUrl] = useState<string | null>(null)
  const [descriptor, setDescriptor] = useState<number[] | null>(null)
  const [setAsAvatar, setSetAsAvatar] = useState(true)

  async function loadFaceApi() {
    if (faceapiRef.current) return faceapiRef.current
    setStatusMsg("Loading face recognition...")
    const faceapi = await import("@vladmandic/face-api")
    const MODEL_URL = "https://cdn.jsdelivr.net/npm/@vladmandic/face-api/model"
    await Promise.all([
      faceapi.nets.tinyFaceDetector.loadFromUri(MODEL_URL),
      faceapi.nets.faceLandmark68TinyNet.loadFromUri(MODEL_URL),
      faceapi.nets.faceRecognitionNet.loadFromUri(MODEL_URL),
    ])
    faceapiRef.current = faceapi
    return faceapi
  }

  function reset() {
    setStage("idle")
    setStatusMsg("")
    setPhotoUrl(null)
    setPhotoDataUrl(null)
    setDescriptor(null)
    if (fileInputRef.current) fileInputRef.current.value = ""
  }

  function close() {
    reset()
    onClose()
  }

  async function handleFile(file: File) {
    if (!file.type.startsWith("image/")) {
      setStage("error"); setStatusMsg("Image files only (png/jpeg/webp)"); return
    }
    if (file.size > 5 * 1024 * 1024) {
      setStage("error"); setStatusMsg("Max 5 MB"); return
    }

    const objectUrl = URL.createObjectURL(file)
    setPhotoUrl(objectUrl)
    setDescriptor(null)
    setStage("processing")
    setStatusMsg("Detecting face...")

    // Read as data URL too — we may need it for the avatar upload.
    const dataUrlPromise = new Promise<string>((resolve, reject) => {
      const reader = new FileReader()
      reader.onload = () => resolve(reader.result as string)
      reader.onerror = reject
      reader.readAsDataURL(file)
    })

    try {
      const faceapi = await loadFaceApi()
      const img = new Image()
      img.crossOrigin = "anonymous"
      await new Promise<void>((resolve, reject) => {
        img.onload = () => resolve()
        img.onerror = reject
        img.src = objectUrl
      })

      const result = await faceapi
        .detectSingleFace(img, new faceapi.TinyFaceDetectorOptions({ inputSize: 512, scoreThreshold: 0.4 }))
        .withFaceLandmarks(true)
        .withFaceDescriptor()

      if (!result) {
        setStage("error")
        setStatusMsg("No face detected — try a clearer, well-lit photo")
        return
      }

      setDescriptor(Array.from(result.descriptor) as number[])
      setPhotoDataUrl(await dataUrlPromise)
      setStage("ready")
      setStatusMsg(`Face detected (${Math.round(result.detection.score * 100)}% confidence)`)
    } catch (err) {
      console.error(err)
      setStage("error")
      setStatusMsg("Couldn't process this image")
    }
  }

  async function save() {
    if (!descriptor) return
    setStage("saving")
    setStatusMsg("Saving face data...")

    try {
      const enrollRes = await fetch("/api/security/face", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "enroll", descriptor }),
      })
      if (!enrollRes.ok) {
        const data = await enrollRes.json().catch(() => ({}))
        setStage("error")
        setStatusMsg(data.error || "Save failed")
        return
      }
      const enrollData = await enrollRes.json().catch(() => ({}))

      let avatarUpdated = false
      if (setAsAvatar && photoDataUrl) {
        setStatusMsg("Updating avatar...")
        const avatarRes = await fetch("/api/auth/avatar", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ dataUrl: photoDataUrl }),
        })
        avatarUpdated = avatarRes.ok
      }

      setStage("done")
      setStatusMsg("Face updated")
      onSuccess?.({
        framesTotal: enrollData.framesStored ?? 1,
        avatarUpdated,
      })
      setTimeout(close, 1100)
    } catch {
      setStage("error")
      setStatusMsg("Network error")
    }
  }

  if (!open) return null

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-sm p-4" onClick={close}>
      <div
        onClick={(e) => e.stopPropagation()}
        className="relative w-full max-w-md overflow-hidden rounded-2xl bg-card border border-border"
      >
        <button
          type="button"
          onClick={close}
          className="absolute top-3 right-3 z-10 text-muted-foreground/60 hover:text-foreground transition-colors"
          aria-label="Close"
        >
          <X size={18} />
        </button>

        <div className="p-6">
          <div className="flex items-center gap-3 mb-4">
            <div className="w-10 h-10 rounded-full bg-primary/10 border border-primary/30 flex items-center justify-center text-primary">
              <ImagePlus size={18} />
            </div>
            <div>
              <p className="text-sm font-semibold text-foreground">Upload a face photo</p>
              <p className="text-xs text-muted-foreground">Adds the photo to your enrolled face data</p>
            </div>
          </div>

          {!photoUrl && stage === "idle" && (
            <button
              type="button"
              onClick={() => fileInputRef.current?.click()}
              className="w-full py-10 rounded-xl border-2 border-dashed border-border hover:border-primary/40 bg-background/50 flex flex-col items-center gap-3 text-muted-foreground hover:text-foreground transition-all group"
            >
              <div className="w-12 h-12 rounded-xl bg-primary/10 border border-primary/20 flex items-center justify-center group-hover:bg-primary/20 transition-all">
                <Upload size={20} className="text-primary" />
              </div>
              <div className="text-center">
                <p className="text-sm font-medium">Choose a photo</p>
                <p className="text-xs text-muted-foreground/60 mt-1">PNG, JPG, or WEBP · clear frontal photo works best</p>
              </div>
            </button>
          )}

          {photoUrl && (
            <div className="flex items-start gap-4 mb-4">
              <div className="relative w-28 h-28 rounded-xl overflow-hidden border border-border flex-shrink-0">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={photoUrl} alt="Face preview" className="w-full h-full object-cover" />
                {stage === "ready" && (
                  <div className="absolute inset-0 border-2 border-emerald-500/60 rounded-xl flex items-end justify-center">
                    <div className="bg-emerald-500/90 text-white text-[9px] font-bold tracking-wider uppercase px-2 py-0.5 rounded-t-md">
                      Face Locked
                    </div>
                  </div>
                )}
                {stage === "error" && descriptor === null && (
                  <div className="absolute inset-0 border-2 border-red-500/60 rounded-xl flex items-end justify-center">
                    <div className="bg-red-500/90 text-white text-[9px] font-bold tracking-wider uppercase px-2 py-0.5 rounded-t-md">
                      No Face
                    </div>
                  </div>
                )}
                {(stage === "processing" || stage === "saving") && (
                  <div className="absolute inset-0 bg-black/60 flex items-center justify-center">
                    <Loader2 size={22} className="animate-spin text-primary" />
                  </div>
                )}
                {stage === "done" && (
                  <div className="absolute inset-0 bg-emerald-500/30 flex items-center justify-center">
                    <CheckCircle2 size={32} className="text-emerald-300" />
                  </div>
                )}
              </div>

              <div className="flex-1 flex flex-col gap-2">
                <p className={`text-xs font-medium ${
                  stage === "ready" || stage === "done" ? "text-emerald-400" :
                  stage === "error" ? "text-red-400" :
                  "text-muted-foreground"
                }`}>
                  {statusMsg || "Working..."}
                </p>
                <div className="flex flex-wrap gap-2">
                  {stage === "error" && (
                    <button
                      type="button"
                      onClick={() => fileInputRef.current?.click()}
                      className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-background border border-border text-xs font-medium text-muted-foreground hover:text-foreground transition-colors"
                    >
                      <RefreshCw size={12} /> Try different photo
                    </button>
                  )}
                  {(stage === "ready" || stage === "error") && (
                    <button
                      type="button"
                      onClick={reset}
                      className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-background border border-border text-xs font-medium text-muted-foreground hover:text-destructive transition-colors"
                    >
                      <X size={12} /> Remove
                    </button>
                  )}
                </div>
              </div>
            </div>
          )}

          {stage === "ready" && (
            <label className="flex items-center gap-2 mb-4 text-xs text-muted-foreground cursor-pointer select-none">
              <input
                type="checkbox"
                checked={setAsAvatar}
                onChange={(e) => setSetAsAvatar(e.target.checked)}
                className="accent-primary"
              />
              Also set this photo as my avatar
            </label>
          )}

          <input
            ref={fileInputRef}
            type="file"
            accept="image/png,image/jpeg,image/webp"
            className="hidden"
            onChange={(e) => {
              const f = e.target.files?.[0]
              if (f) handleFile(f)
            }}
          />

          {stage === "ready" && (
            <div className="flex gap-2">
              <button
                type="button"
                onClick={close}
                className="flex-1 py-2.5 rounded-xl border border-border text-sm font-medium text-muted-foreground hover:text-foreground transition-all"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={save}
                disabled={!descriptor}
                className="flex-1 py-2.5 rounded-xl bg-primary text-primary-foreground text-sm font-semibold hover:opacity-90 transition-all flex items-center justify-center gap-2 disabled:opacity-40"
              >
                <CheckCircle2 size={14} /> Save face
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
