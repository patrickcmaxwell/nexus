"use client"

import { useState, useEffect, useRef } from "react"
import {
  UserPlus, Users, Copy, Check, Trash2, Loader2,
  Shield, ShieldCheck, ShieldAlert, Upload, X, RefreshCw,
  Scan, CheckCircle2, Link2,
} from "lucide-react"

type Member = {
  id: string
  display_name: string
  handle: string | null
  role: string
  status: string
  avatar_url: string | null
  created_at: string
}

type InviteResult = {
  member: { id: string; display_name: string; invite_token: string }
  inviteUrl: string
}

const STATUS_STYLES: Record<string, { bg: string; text: string; icon: typeof ShieldCheck }> = {
  active:   { bg: "bg-emerald-500/10 border-emerald-500/30", text: "text-emerald-400", icon: ShieldCheck },
  invited:  { bg: "bg-amber-500/10 border-amber-500/30",    text: "text-amber-400",   icon: Shield },
  disabled: { bg: "bg-red-500/10 border-red-500/30",         text: "text-red-400",     icon: ShieldAlert },
}

export default function TeamPage() {
  const [members, setMembers] = useState<Member[]>([])
  const [loading, setLoading] = useState(true)
  const [showInvite, setShowInvite] = useState(false)
  const [inviteName, setInviteName] = useState("")
  const [inviteEmail, setInviteEmail] = useState("")
  const [inviteRole, setInviteRole] = useState("observer")
  const [inviting, setInviting] = useState(false)
  const [inviteResult, setInviteResult] = useState<InviteResult | null>(null)
  const [copied, setCopied] = useState(false)
  const [updatingRole, setUpdatingRole] = useState<string | null>(null)

  // Face photo upload
  const fileInputRef = useRef<HTMLInputElement>(null)
  const [photoUrl, setPhotoUrl] = useState<string | null>(null)
  const [faceStatus, setFaceStatus] = useState<"idle" | "loading" | "processing" | "done" | "failed">("idle")
  const [faceDescriptor, setFaceDescriptor] = useState<number[] | null>(null)
  const [faceStatusMsg, setFaceStatusMsg] = useState("")
  const faceapiRef = useRef<any>(null)

  useEffect(() => {
    loadMembers()
  }, [])

  async function loadMembers() {
    setLoading(true)
    try {
      const res = await fetch("/api/team/invite")
      if (res.ok) {
        const data = await res.json()
        setMembers(data.members ?? [])
      }
    } finally {
      setLoading(false)
    }
  }

  // ── Face extraction from uploaded photo ──────────────────────────────────
  async function loadFaceApi() {
    if (faceapiRef.current) return faceapiRef.current
    setFaceStatus("loading")
    setFaceStatusMsg("Loading face recognition engine...")
    const faceapi = await import("@vladmandic/face-api")
    const MODEL_URL = "https://cdn.jsdelivr.net/npm/@vladmandic/face-api/model"
    await faceapi.nets.tinyFaceDetector.loadFromUri(MODEL_URL)
    await faceapi.nets.faceLandmark68TinyNet.loadFromUri(MODEL_URL)
    await faceapi.nets.faceRecognitionNet.loadFromUri(MODEL_URL)
    faceapiRef.current = faceapi
    return faceapi
  }

  function handlePhotoSelect(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    const url = URL.createObjectURL(file)
    setPhotoUrl(url)
    setFaceDescriptor(null)
    setFaceStatus("idle")
    setFaceStatusMsg("")
    extractFaceFromPhoto(url)
  }

  async function extractFaceFromPhoto(url: string) {
    setFaceStatus("loading")
    try {
      const faceapi = await loadFaceApi()
      setFaceStatus("processing")
      setFaceStatusMsg("Detecting face in photo...")

      const img = new Image()
      img.crossOrigin = "anonymous"
      await new Promise<void>((resolve, reject) => {
        img.onload = () => resolve()
        img.onerror = reject
        img.src = url
      })

      const result = await faceapi
        .detectSingleFace(img, new faceapi.TinyFaceDetectorOptions({ inputSize: 512, scoreThreshold: 0.4 }))
        .withFaceLandmarks(true)
        .withFaceDescriptor()

      if (result) {
        setFaceDescriptor(Array.from(result.descriptor) as number[])
        setFaceStatus("done")
        setFaceStatusMsg(`Face detected — ${Math.round(result.detection.score * 100)}% confidence`)
      } else {
        setFaceStatus("failed")
        setFaceStatusMsg("No face detected — try a clearer photo")
      }
    } catch (err) {
      setFaceStatus("failed")
      setFaceStatusMsg("Failed to process image")
      console.error(err)
    }
  }

  function clearPhoto() {
    setPhotoUrl(null)
    setFaceDescriptor(null)
    setFaceStatus("idle")
    setFaceStatusMsg("")
    if (fileInputRef.current) fileInputRef.current.value = ""
  }

  // ── Invite submission ────────────────────────────────────────────────────
  async function handleInvite(e: React.FormEvent) {
    e.preventDefault()
    if (!inviteName.trim()) return
    setInviting(true)
    try {
      const res = await fetch("/api/team/invite", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: inviteName.trim(),
          email: inviteEmail.trim() || undefined,
          role: inviteRole,
          seedFaceDescriptor: faceDescriptor,
        }),
      })
      if (res.ok) {
        const data = await res.json()
        setInviteResult(data)
        loadMembers()
      }
    } finally {
      setInviting(false)
    }
  }

  function resetInviteForm() {
    setShowInvite(false)
    setInviteName("")
    setInviteEmail("")
    setInviteRole("observer")
    setInviteResult(null)
    clearPhoto()
  }

  async function copyInviteLink() {
    if (!inviteResult) return
    await navigator.clipboard.writeText(inviteResult.inviteUrl)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  async function handleDisable(id: string) {
    if (!confirm("Disable this human?")) return
    await fetch("/api/team/invite", {
      method: "DELETE",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id }),
    })
    loadMembers()
  }

  async function updateRole(id: string, newRole: string) {
    setUpdatingRole(id)
    await fetch("/api/team/invite", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id, role: newRole }),
    })
    setUpdatingRole(null)
    loadMembers()
  }

  // ── Render ───────────────────────────────────────────────────────────────
  return (
    <div className="flex flex-col h-[calc(100dvh-5rem)] md:h-screen bg-background text-foreground font-sans overflow-hidden">

      {/* Header */}
      <div className="flex items-center justify-between gap-4 px-5 md:px-8 py-5 border-b border-border flex-shrink-0">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-primary/10 border border-primary/20 flex items-center justify-center">
            <Users size={18} className="text-primary" />
          </div>
          <div>
            <h1 className="text-lg font-bold text-foreground">Humans</h1>
            <p className="text-xs text-muted-foreground">{members.length} human{members.length !== 1 ? "s" : ""}</p>
          </div>
        </div>
        <button
          onClick={() => { setShowInvite(true); setInviteResult(null) }}
          className="flex items-center gap-2 px-4 py-2.5 rounded-xl bg-primary/10 border border-primary/30 text-primary text-sm font-semibold hover:bg-primary/20 transition-all"
        >
          <UserPlus size={15} />
          Add Human
        </button>
      </div>

      <div className="flex-1 overflow-y-auto px-5 md:px-8 py-6">
        <div className="max-w-3xl mx-auto">

          {/* ── Invite Panel ── */}
          {showInvite && (
            <div className="mb-8 p-6 rounded-2xl border border-primary/20 bg-card">
              {!inviteResult ? (
                <form onSubmit={handleInvite} className="flex flex-col gap-5">
                  <div className="flex items-center justify-between">
                    <h2 className="text-base font-bold text-foreground flex items-center gap-2">
                      <UserPlus size={16} className="text-primary" />
                      Add a Human
                    </h2>
                    <button type="button" onClick={resetInviteForm} className="text-muted-foreground hover:text-foreground transition-colors">
                      <X size={16} />
                    </button>
                  </div>

                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div>
                      <label className="block text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-1.5">Name *</label>
                      <input
                        type="text"
                        value={inviteName}
                        onChange={e => setInviteName(e.target.value)}
                        placeholder="Londynn"
                        autoFocus
                        className="w-full px-4 py-2.5 rounded-xl bg-background border border-border text-sm text-foreground placeholder:text-muted-foreground/40 focus:outline-none focus:border-primary/50 focus:ring-2 focus:ring-primary/20 transition-all"
                      />
                    </div>
                    <div>
                      <label className="block text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-1.5">Email (optional)</label>
                      <input
                        type="email"
                        value={inviteEmail}
                        onChange={e => setInviteEmail(e.target.value)}
                        placeholder="londynn@example.com"
                        className="w-full px-4 py-2.5 rounded-xl bg-background border border-border text-sm text-foreground placeholder:text-muted-foreground/40 focus:outline-none focus:border-primary/50 focus:ring-2 focus:ring-primary/20 transition-all"
                      />
                    </div>
                  </div>

                  <div>
                    <label className="block text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-1.5">Access Level *</label>
                    <select
                      value={inviteRole}
                      onChange={(e) => setInviteRole(e.target.value)}
                      className="w-full px-4 py-2.5 rounded-xl bg-background border border-border text-sm text-foreground focus:outline-none focus:border-primary/50 focus:ring-2 focus:ring-primary/20 transition-all"
                    >
                      <option value="observer">Observer (Public data only)</option>
                      <option value="collaborator">Collaborator (Shared data you explicitly assign)</option>
                      <option value="operator">Operator (Can create agents & operations)</option>
                      <option value="admin">Admin (Full access except private memory)</option>
                    </select>
                  </div>

                  {/* Face Upload */}
                  <div>
                    <label className="block text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-1.5">
                      Seed Face Photo (enables instant face login)
                    </label>

                    {!photoUrl ? (
                      <button
                        type="button"
                        onClick={() => fileInputRef.current?.click()}
                        className="w-full py-8 rounded-xl border-2 border-dashed border-border hover:border-primary/40 bg-background/50 flex flex-col items-center gap-3 text-muted-foreground hover:text-foreground transition-all group"
                      >
                        <div className="w-12 h-12 rounded-xl bg-primary/10 border border-primary/20 flex items-center justify-center group-hover:bg-primary/20 transition-all">
                          <Upload size={20} className="text-primary" />
                        </div>
                        <div className="text-center">
                          <p className="text-sm font-medium">Upload a photo of their face</p>
                          <p className="text-xs text-muted-foreground/60 mt-1">JPG, PNG — clear frontal photo works best</p>
                        </div>
                      </button>
                    ) : (
                      <div className="flex items-start gap-4">
                        <div className="relative w-32 h-32 rounded-xl overflow-hidden border border-border flex-shrink-0">
                          {/* eslint-disable-next-line @next/next/no-img-element */}
                          <img src={photoUrl} alt="Face preview" className="w-full h-full object-cover" />
                          {faceStatus === "done" && (
                            <div className="absolute inset-0 border-2 border-emerald-500/60 rounded-xl flex items-end justify-center">
                              <div className="bg-emerald-500/90 text-white text-[9px] font-bold tracking-wider uppercase px-2 py-0.5 rounded-t-md">
                                FACE LOCKED
                              </div>
                            </div>
                          )}
                          {faceStatus === "failed" && (
                            <div className="absolute inset-0 border-2 border-red-500/60 rounded-xl flex items-end justify-center">
                              <div className="bg-red-500/90 text-white text-[9px] font-bold tracking-wider uppercase px-2 py-0.5 rounded-t-md">
                                NO FACE
                              </div>
                            </div>
                          )}
                          {(faceStatus === "loading" || faceStatus === "processing") && (
                            <div className="absolute inset-0 bg-black/50 flex items-center justify-center">
                              <Loader2 size={20} className="animate-spin text-primary" />
                            </div>
                          )}
                        </div>

                        <div className="flex-1 flex flex-col gap-2">
                          <p className={`text-xs font-medium ${
                            faceStatus === "done" ? "text-emerald-400" :
                            faceStatus === "failed" ? "text-red-400" :
                            "text-muted-foreground"
                          }`}>
                            {faceStatusMsg || "Processing..."}
                          </p>

                          <div className="flex gap-2">
                            {faceStatus === "failed" && (
                              <button
                                type="button"
                                onClick={() => extractFaceFromPhoto(photoUrl!)}
                                className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-background border border-border text-xs font-medium text-muted-foreground hover:text-foreground transition-colors"
                              >
                                <RefreshCw size={12} /> Retry
                              </button>
                            )}
                            <button
                              type="button"
                              onClick={clearPhoto}
                              className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-background border border-border text-xs font-medium text-muted-foreground hover:text-destructive transition-colors"
                            >
                              <X size={12} /> Remove
                            </button>
                          </div>

                          {faceStatus === "done" && (
                            <p className="text-[10px] text-muted-foreground/60 mt-1">
                              This face will be used for their initial login. They can re-scan once they&apos;re in.
                            </p>
                          )}
                        </div>
                      </div>
                    )}

                    <input ref={fileInputRef} type="file" accept="image/*" className="hidden" onChange={handlePhotoSelect} />
                  </div>

                  <button
                    type="submit"
                    disabled={!inviteName.trim() || inviting || faceStatus === "loading" || faceStatus === "processing"}
                    className="w-full py-3 rounded-xl bg-primary/10 border border-primary/30 text-primary text-sm font-semibold hover:bg-primary/20 disabled:opacity-40 disabled:cursor-not-allowed transition-all flex items-center justify-center gap-2"
                  >
                    {inviting ? (
                      <><Loader2 size={14} className="animate-spin" /> Creating invite...</>
                    ) : (
                      <><UserPlus size={14} /> Generate Invite Link</>
                    )}
                  </button>
                </form>
              ) : (
                <div className="flex flex-col gap-4">
                  <div className="flex items-center gap-3">
                    <div className="w-10 h-10 rounded-full bg-emerald-500/10 border border-emerald-500/30 flex items-center justify-center">
                      <CheckCircle2 size={20} className="text-emerald-400" />
                    </div>
                    <div>
                      <p className="text-sm font-bold text-foreground">Invite created for {inviteResult.member.display_name}</p>
                      <p className="text-xs text-muted-foreground">Send them this link to get started</p>
                    </div>
                  </div>

                  <div className="flex items-center gap-2 p-3 rounded-xl bg-background border border-border">
                    <Link2 size={14} className="text-muted-foreground flex-shrink-0" />
                    <code className="flex-1 text-xs text-foreground/80 truncate font-mono">{inviteResult.inviteUrl}</code>
                    <button
                      onClick={copyInviteLink}
                      className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-primary/10 border border-primary/30 text-xs font-semibold text-primary hover:bg-primary/20 transition-all flex-shrink-0"
                    >
                      {copied ? <><Check size={12} /> Copied!</> : <><Copy size={12} /> Copy</>}
                    </button>
                  </div>

                  {faceDescriptor && (
                    <div className="flex items-center gap-2 p-3 rounded-xl bg-emerald-500/5 border border-emerald-500/20">
                      <Scan size={14} className="text-emerald-400 flex-shrink-0" />
                      <p className="text-xs text-emerald-400">Seed face included — they can log in with face recognition immediately</p>
                    </div>
                  )}

                  <div className="flex gap-3">
                    <button
                      onClick={resetInviteForm}
                      className="flex-1 py-2.5 rounded-xl border border-border text-sm font-medium text-muted-foreground hover:text-foreground hover:border-foreground/30 transition-all"
                    >
                      Done
                    </button>
                    <button
                      onClick={() => { setInviteResult(null); setInviteName(""); setInviteEmail(""); clearPhoto() }}
                      className="flex-1 py-2.5 rounded-xl bg-primary/10 border border-primary/30 text-sm font-semibold text-primary hover:bg-primary/20 transition-all"
                    >
                      Invite Another
                    </button>
                  </div>
                </div>
              )}
            </div>
          )}

          {/* ── Members List ── */}
          {loading ? (
            <div className="flex items-center justify-center h-40">
              <Loader2 size={20} className="animate-spin text-primary" />
            </div>
          ) : members.length === 0 ? (
            <div className="text-center py-16">
              <Users size={40} className="mx-auto mb-4 text-muted-foreground/30" />
              <p className="text-sm text-muted-foreground">No humans yet</p>
              <p className="text-xs text-muted-foreground/60 mt-1">Add someone to get started</p>
            </div>
          ) : (
            <div className="flex flex-col gap-3">
              {members.map(member => {
                const style = STATUS_STYLES[member.status] ?? STATUS_STYLES.active
                const StatusIcon = style.icon
                return (
                  <div
                    key={member.id}
                    className={`flex items-center gap-4 p-4 rounded-xl border ${style.bg} group transition-all hover:shadow-md`}
                  >
                    <div className="w-11 h-11 rounded-xl bg-primary/10 border border-primary/20 flex items-center justify-center flex-shrink-0">
                      <span className="text-sm font-bold text-primary">{member.display_name.charAt(0).toUpperCase()}</span>
                    </div>

                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <p className="text-sm font-semibold text-foreground truncate">{member.display_name}</p>
                        {updatingRole === member.id ? (
                          <Loader2 size={12} className="animate-spin text-primary" />
                        ) : (
                          <select
                            value={member.role}
                            onChange={(e) => updateRole(member.id, e.target.value)}
                            disabled={member.role === "admin"}
                            title={member.role === "admin" ? "Admins cannot be demoted directly" : "Change role"}
                            className={`text-[10px] font-bold uppercase tracking-wider px-2 py-0.5 rounded-full border bg-transparent focus:outline-none focus:ring-1 focus:ring-primary ${style.bg} ${style.text} ${member.role !== "admin" ? 'cursor-pointer hover:opacity-80' : 'cursor-not-allowed'}`}
                          >
                            <option value="observer" className="bg-background text-foreground">OBSERVER</option>
                            <option value="collaborator" className="bg-background text-foreground">COLLABORATOR</option>
                            <option value="operator" className="bg-background text-foreground">OPERATOR</option>
                            <option value="admin" className="bg-background text-foreground">ADMIN</option>
                          </select>
                        )}
                      </div>
                      <div className="flex items-center gap-3 mt-0.5">
                        {member.handle && (
                          <p className="text-xs text-muted-foreground truncate">@{member.handle}</p>
                        )}
                        <div className={`flex items-center gap-1 ${style.text}`}>
                          <StatusIcon size={11} />
                          <span className="text-[10px] font-medium capitalize">{member.status}</span>
                        </div>
                      </div>
                    </div>

                    {member.role !== "admin" && (
                      <button
                        onClick={() => handleDisable(member.id)}
                        className="opacity-0 group-hover:opacity-100 p-2 text-muted-foreground/40 hover:text-destructive transition-all rounded-lg"
                        title="Disable member"
                      >
                        <Trash2 size={14} />
                      </button>
                    )}
                  </div>
                )
              })}
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
