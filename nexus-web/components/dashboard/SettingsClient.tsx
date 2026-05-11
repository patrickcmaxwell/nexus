"use client"

import { useCallback, useEffect, useRef, useState } from "react"
import { useRouter } from "next/navigation"
import {
  User, Lock, Scan, LogOut, Loader2, Camera, Trash2, Upload,
  CheckCircle2, ShieldAlert, Monitor, KeyRound,
} from "lucide-react"
import FaceReenrollModal from "@/components/security/FaceReenrollModal"
import { UserAvatar } from "@/components/ui/UserAvatar"
import ConnectionsPanel from "@/components/dashboard/settings/ConnectionsPanel"

type Initial = {
  humanId: string
  email: string
  displayName: string
  handle: string | null
  role: string
  isOwner: boolean
  authMethod: string | null
  avatarUrl: string | null
}

type Session = {
  id: string
  created_at: string
  last_verified_at: string
  expires_at: string
  auth_method: string
  device_label: string | null
  ip_address: string | null
  current: boolean
}

export default function SettingsClient({ initial }: { initial: Initial }) {
  const router = useRouter()

  // ── Identity card state ──────────────────────────────────────────────────
  const [displayName, setDisplayName] = useState(initial.displayName)
  const [handle, setHandle] = useState(initial.handle ?? "")
  const [avatarUrl, setAvatarUrl] = useState(initial.avatarUrl)
  const [identitySaving, setIdentitySaving] = useState(false)
  const [identityMsg, setIdentityMsg] = useState<{ ok: boolean; text: string } | null>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)

  // ── PIN card state ───────────────────────────────────────────────────────
  const [currentPin, setCurrentPin] = useState("")
  const [newPin, setNewPin] = useState("")
  const [confirmPin, setConfirmPin] = useState("")
  const [pinSaving, setPinSaving] = useState(false)
  const [pinMsg, setPinMsg] = useState<{ ok: boolean; text: string } | null>(null)

  // ── Face card state ──────────────────────────────────────────────────────
  const [faceModalOpen, setFaceModalOpen] = useState(false)
  const [faceMsg, setFaceMsg] = useState<{ ok: boolean; text: string } | null>(null)

  // ── Sessions card state ──────────────────────────────────────────────────
  const [sessions, setSessions] = useState<Session[]>([])
  const [sessionsLoading, setSessionsLoading] = useState(true)
  const [sessionActionId, setSessionActionId] = useState<string | null>(null)

  const loadSessions = useCallback(async () => {
    setSessionsLoading(true)
    try {
      const res = await fetch("/api/auth/sessions", { credentials: "include" })
      if (res.ok) {
        const data = await res.json()
        setSessions(data.sessions ?? [])
      }
    } finally {
      setSessionsLoading(false)
    }
  }, [])

  useEffect(() => { loadSessions() }, [loadSessions])

  // ── Handlers ─────────────────────────────────────────────────────────────
  async function saveIdentity(e: React.FormEvent) {
    e.preventDefault()
    setIdentitySaving(true)
    setIdentityMsg(null)
    try {
      const res = await fetch("/api/auth/me", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          displayName: displayName.trim(),
          handle: handle.trim() === "" ? null : handle.trim(),
        }),
      })
      const data = await res.json().catch(() => ({}))
      if (res.ok) {
        setIdentityMsg({ ok: true, text: "Saved" })
        router.refresh()
      } else {
        setIdentityMsg({ ok: false, text: data.error || "Save failed" })
      }
    } catch {
      setIdentityMsg({ ok: false, text: "Network error" })
    } finally {
      setIdentitySaving(false)
    }
  }

  async function uploadAvatar(file: File) {
    if (!file.type.startsWith("image/")) {
      setIdentityMsg({ ok: false, text: "Image files only (png/jpeg/webp)" })
      return
    }
    if (file.size > 3 * 1024 * 1024) {
      setIdentityMsg({ ok: false, text: "Max 3 MB" })
      return
    }
    setIdentitySaving(true)
    setIdentityMsg(null)
    const reader = new FileReader()
    reader.onload = async () => {
      try {
        const res = await fetch("/api/auth/avatar", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ dataUrl: reader.result }),
        })
        const data = await res.json().catch(() => ({}))
        if (res.ok) {
          setAvatarUrl(data.avatarUrl)
          setIdentityMsg({ ok: true, text: "Avatar updated" })
          router.refresh()
        } else {
          setIdentityMsg({ ok: false, text: data.error || "Upload failed" })
        }
      } finally {
        setIdentitySaving(false)
      }
    }
    reader.readAsDataURL(file)
  }

  async function removeAvatar() {
    if (!confirm("Remove your avatar?")) return
    setIdentitySaving(true)
    try {
      const res = await fetch("/api/auth/avatar", { method: "DELETE" })
      if (res.ok) {
        setAvatarUrl(null)
        setIdentityMsg({ ok: true, text: "Avatar removed" })
        router.refresh()
      }
    } finally {
      setIdentitySaving(false)
    }
  }

  async function changePin(e: React.FormEvent) {
    e.preventDefault()
    setPinMsg(null)
    if (newPin.length < 4) {
      setPinMsg({ ok: false, text: "PIN must be 4+ digits" })
      return
    }
    if (newPin !== confirmPin) {
      setPinMsg({ ok: false, text: "PINs don't match" })
      return
    }
    setPinSaving(true)
    try {
      const res = await fetch("/api/auth/change-pin", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ currentPin, newPin }),
      })
      const data = await res.json().catch(() => ({}))
      if (res.ok) {
        setPinMsg({ ok: true, text: "PIN updated. Other sessions signed out." })
        setCurrentPin(""); setNewPin(""); setConfirmPin("")
        loadSessions()
      } else {
        setPinMsg({ ok: false, text: data.error || "PIN change failed" })
      }
    } catch {
      setPinMsg({ ok: false, text: "Network error" })
    } finally {
      setPinSaving(false)
    }
  }

  async function revokeSession(id: string) {
    setSessionActionId(id)
    try {
      const res = await fetch(`/api/auth/sessions/${id}`, { method: "DELETE" })
      if (res.ok) {
        const sess = sessions.find((s) => s.id === id)
        if (sess?.current) {
          window.location.replace("/")
          return
        }
        loadSessions()
      }
    } finally {
      setSessionActionId(null)
    }
  }

  async function signOutEverywhere() {
    if (!confirm("Sign out every other device? Your current session stays.")) return
    setSessionActionId("others")
    try {
      const res = await fetch("/api/auth/sessions", {
        method: "DELETE",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ scope: "others" }),
      })
      if (res.ok) loadSessions()
    } finally {
      setSessionActionId(null)
    }
  }

  async function logoutCurrent() {
    if (!confirm("Sign out of this device?")) return
    await fetch("/api/security/logout", { method: "POST" }).catch(() => {})
    window.location.replace("/")
  }

  // ── Render ───────────────────────────────────────────────────────────────
  return (
    <div className="min-h-screen p-4 sm:p-6 md:p-10 max-w-3xl mx-auto">
      <div className="mb-8">
        <h1 className="text-2xl font-semibold tracking-tight text-foreground">Your account</h1>
        <p className="text-sm text-muted-foreground mt-2">Manage how you appear in Nexus and how you sign in.</p>
      </div>

      {/* IDENTITY */}
      <Card title="Identity" icon={<User size={16} />}>
        <div className="flex flex-col sm:flex-row items-center sm:items-start gap-5">
          <div className="flex flex-col items-center gap-3">
            <UserAvatar name={displayName} src={avatarUrl} size="xl" ring="muted" />
            <div className="flex gap-2">
              <button
                type="button"
                onClick={() => fileInputRef.current?.click()}
                className="px-3 py-1.5 text-xs font-medium text-muted-foreground hover:text-foreground border border-border rounded-lg hover:bg-muted transition-colors flex items-center gap-1.5"
              >
                <Upload size={12} /> Upload
              </button>
              {avatarUrl && (
                <button
                  type="button"
                  onClick={removeAvatar}
                  className="px-3 py-1.5 text-xs font-medium text-muted-foreground hover:text-destructive border border-border rounded-lg hover:bg-destructive/10 transition-colors flex items-center gap-1.5"
                >
                  <Trash2 size={12} />
                </button>
              )}
              <input
                ref={fileInputRef}
                type="file"
                accept="image/png,image/jpeg,image/webp"
                className="hidden"
                onChange={(e) => { const f = e.target.files?.[0]; if (f) uploadAvatar(f); e.target.value = "" }}
              />
            </div>
          </div>

          <form onSubmit={saveIdentity} className="flex-1 flex flex-col gap-3 w-full">
            <Field label="Display name">
              <input
                type="text"
                value={displayName}
                onChange={(e) => setDisplayName(e.target.value)}
                maxLength={80}
                className={fieldClass}
              />
            </Field>
            <Field label="Handle (optional)">
              <input
                type="text"
                value={handle}
                onChange={(e) => setHandle(e.target.value)}
                placeholder="lowercase, numbers, _"
                maxLength={30}
                className={fieldClass}
              />
            </Field>
            <Field label="Email">
              <input type="text" value={initial.email} readOnly className={`${fieldClass} opacity-60`} />
            </Field>
            <Field label="Role">
              <input type="text" value={initial.role + (initial.isOwner ? " (owner)" : "")} readOnly className={`${fieldClass} opacity-60`} />
            </Field>

            {identityMsg && (
              <p className={`text-sm ${identityMsg.ok ? "text-nexus-success" : "text-nexus-danger"}`}>
                {identityMsg.text}
              </p>
            )}

            <button
              type="submit"
              disabled={identitySaving}
              className="self-start mt-1 px-4 py-2 text-sm font-medium rounded-lg bg-primary text-primary-foreground hover:opacity-90 transition-opacity flex items-center gap-2 disabled:opacity-40"
            >
              {identitySaving ? <Loader2 size={14} className="animate-spin" /> : <CheckCircle2 size={14} />}
              Save changes
            </button>
          </form>
        </div>
      </Card>

      {/* PIN */}
      <Card title="Change PIN" icon={<Lock size={16} />}>
        <form onSubmit={changePin} className="flex flex-col gap-3 max-w-sm">
          <Field label="Current PIN">
            <input
              type="password"
              inputMode="numeric"
              value={currentPin}
              onChange={(e) => setCurrentPin(e.target.value.replace(/\D/g, ""))}
              maxLength={8}
              className={fieldClass}
            />
          </Field>
          <Field label="New PIN (4+ digits)">
            <input
              type="password"
              inputMode="numeric"
              value={newPin}
              onChange={(e) => setNewPin(e.target.value.replace(/\D/g, ""))}
              maxLength={8}
              className={fieldClass}
            />
          </Field>
          <Field label="Confirm new PIN">
            <input
              type="password"
              inputMode="numeric"
              value={confirmPin}
              onChange={(e) => setConfirmPin(e.target.value.replace(/\D/g, ""))}
              maxLength={8}
              className={fieldClass}
            />
          </Field>

          {pinMsg && (
            <p className={`text-sm ${pinMsg.ok ? "text-nexus-success" : "text-nexus-danger"}`}>
              {pinMsg.text}
            </p>
          )}

          <button
            type="submit"
            disabled={pinSaving || !currentPin || !newPin || !confirmPin}
            className="self-start px-4 py-2 text-sm font-medium rounded-lg bg-primary text-primary-foreground hover:opacity-90 transition-opacity flex items-center gap-2 disabled:opacity-40"
          >
            {pinSaving ? <Loader2 size={14} className="animate-spin" /> : <KeyRound size={14} />}
            Update PIN
          </button>
        </form>
      </Card>

      {/* FACE */}
      <Card title="Face recognition" icon={<Scan size={16} />}>
        <p className="text-xs text-muted-foreground mb-3 max-w-md">
          Re-enroll captures five fresh angles. Helps when lighting changes,
          you grow a beard, or recognition has been flaky.
        </p>
        {faceMsg && (
          <p className={`text-sm mb-3 ${faceMsg.ok ? "text-nexus-success" : "text-nexus-danger"}`}>
            {faceMsg.text}
          </p>
        )}
        <button
          type="button"
          onClick={() => setFaceModalOpen(true)}
          className="px-4 py-2 text-sm font-medium rounded-lg bg-primary text-primary-foreground hover:opacity-90 transition-opacity flex items-center gap-2"
        >
          <Camera size={14} /> Re-enroll face
        </button>
      </Card>

      {/* SESSIONS */}
      <Card title="Active sessions" icon={<Monitor size={16} />}>
        <p className="text-xs text-muted-foreground mb-3">
          Devices currently signed in to your account. Revoke any you don't recognize.
        </p>

        {sessionsLoading ? (
          <Loader2 size={16} className="animate-spin text-muted-foreground" />
        ) : sessions.length === 0 ? (
          <p className="text-xs text-muted-foreground">No active sessions found.</p>
        ) : (
          <ul className="flex flex-col gap-2 mb-4">
            {sessions.map((s) => (
              <li
                key={s.id}
                className={`flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2 sm:gap-3 px-4 py-3 rounded-lg border ${
                  s.current
                    ? "bg-primary/5 border-primary/40"
                    : "bg-transparent border-border"
                }`}
              >
                <div className="flex flex-col min-w-0 gap-0.5">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className={`text-sm font-medium ${s.current ? "text-primary" : "text-foreground"}`}>
                      {s.device_label ?? "Unknown device"}
                    </span>
                    {s.current && (
                      <span className="text-xs px-2 py-0.5 rounded-md bg-primary/15 text-primary">
                        This device
                      </span>
                    )}
                  </div>
                  <span className="text-xs text-muted-foreground flex flex-wrap gap-x-2 gap-y-0.5">
                    <span>Signed in via {authMethodLabel(s.auth_method)}</span>
                    <span>· Last active {timeAgo(s.last_verified_at)}</span>
                    {s.ip_address && <span className="font-mono">· {s.ip_address}</span>}
                  </span>
                </div>
                <button
                  type="button"
                  onClick={() => revokeSession(s.id)}
                  disabled={sessionActionId === s.id}
                  className="self-start sm:self-auto px-3 py-1.5 text-xs font-medium text-muted-foreground hover:text-destructive border border-border hover:border-destructive/50 hover:bg-destructive/10 rounded-lg flex items-center gap-1.5 disabled:opacity-40 transition-colors"
                >
                  {sessionActionId === s.id ? <Loader2 size={11} className="animate-spin" /> : <Trash2 size={11} />}
                  Revoke
                </button>
              </li>
            ))}
          </ul>
        )}

        <div className="flex flex-wrap gap-2">
          <button
            type="button"
            onClick={signOutEverywhere}
            disabled={sessionActionId === "others" || sessions.filter((s) => !s.current).length === 0}
            className="px-4 py-2 text-sm font-medium rounded-lg text-destructive border border-destructive/40 hover:bg-destructive/10 transition-colors flex items-center gap-2 disabled:opacity-40"
          >
            <ShieldAlert size={14} /> Sign out other devices
          </button>
          <button
            type="button"
            onClick={logoutCurrent}
            className="px-4 py-2 text-sm font-medium rounded-lg text-muted-foreground hover:text-foreground border border-border hover:bg-muted transition-colors flex items-center gap-2"
          >
            <LogOut size={14} /> Sign out this device
          </button>
        </div>
      </Card>

      <div className="mb-5">
        <ConnectionsPanel />
      </div>

      <FaceReenrollModal
        open={faceModalOpen}
        onClose={() => setFaceModalOpen(false)}
        onSuccess={(n) => setFaceMsg({ ok: true, text: `${n} frame${n === 1 ? "" : "s"} enrolled` })}
      />
    </div>
  )
}

// ── Visual primitives ──────────────────────────────────────────────────────
//
// Clean Apple/Linear baseline: soft rounded cards with hairline borders, no
// HUD corner brackets, no neon-mono labels. Inputs use the theme tokens.

const fieldClass =
  "w-full px-3 py-2.5 text-sm bg-background border border-border rounded-lg focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20 text-foreground transition-colors"

function Card({ title, icon, children }: { title: string; icon: React.ReactNode; children: React.ReactNode }) {
  return (
    <section className="mb-5 rounded-2xl bg-card border border-border p-5 md:p-6">
      <div className="flex items-center gap-2.5 mb-5">
        <div className="text-muted-foreground">{icon}</div>
        <h2 className="text-base font-semibold text-foreground">{title}</h2>
      </div>
      {children}
    </section>
  )
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="flex flex-col gap-1.5">
      <span className="text-sm font-medium text-foreground">{label}</span>
      {children}
    </label>
  )
}

function timeAgo(iso: string): string {
  const ms = Date.now() - new Date(iso).getTime()
  const m = Math.round(ms / 60000)
  if (m < 1) return "just now"
  if (m < 60) return `${m}m ago`
  const h = Math.round(m / 60)
  if (h < 24) return `${h}h ago`
  const d = Math.round(h / 24)
  return `${d}d ago`
}

function authMethodLabel(method: string): string {
  if (method === "pin") return "Email + PIN"
  if (method === "face") return "Face scan"
  if (method === "passphrase") return "Passphrase (legacy)"
  return method
}
