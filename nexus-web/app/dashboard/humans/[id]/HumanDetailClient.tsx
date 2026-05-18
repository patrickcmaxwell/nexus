"use client"

// Per-member detail. Apple/Linear-style sectioning. Tabs for Profile /
// Sessions / Activity, plus an admin actions panel when the viewer can
// manage this member.

import { useState } from "react"
import { useRouter } from "next/navigation"
import {
  Mail, Shield, Calendar, Lock, RotateCcw, Trash2, AlertTriangle,
  CheckCircle2, Loader2, MessageSquare, Workflow, Unlock, ScanFace, Link2, Copy, Check, Send, X,
} from "lucide-react"
import { UserAvatar } from "@/components/ui/UserAvatar"
import { Card, Button, Pill, Section, Tabs, EmptyState } from "@/components/ui/primitives"

type Member = {
  id: string
  display_name: string
  handle: string | null
  email: string | null
  role: string
  is_owner: boolean
  status: string
  avatar_url: string | null
  created_at: string
}

type Session = {
  id: string
  auth_method: string
  last_verified_at: string
  expires_at: string
  invalidated: boolean
  created_at: string
}

type Conv = { id: string; title: string; updated_at: string }
type Op = { id: string; name: string; status: string; priority: string; updated_at: string }

export default function HumanDetailClient({
  member, sessions, recentConversations, recentOperations, canManage, isSelf,
}: {
  member: Member
  sessions: Session[]
  recentConversations: Conv[]
  recentOperations: Op[]
  canManage: boolean
  isSelf: boolean
}) {
  const router = useRouter()
  const [tab, setTab] = useState("profile")
  const [actionMsg, setActionMsg] = useState<{ ok: boolean; text: string } | null>(null)
  const [acting, setActing] = useState(false)
  const [resetLink, setResetLink] = useState<{ url: string; name: string } | null>(null)
  const [linkCopied, setLinkCopied] = useState(false)
  const [showDelete, setShowDelete] = useState(false)
  const [deleteConfirmText, setDeleteConfirmText] = useState("")

  async function lockMember() {
    if (!confirm(`Lock ${member.display_name}? They'll be signed out and unable to sign back in until you unlock them.`)) return
    setActing(true)
    setActionMsg(null)
    try {
      const res = await fetch("/api/admin/lock-user", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ targetHumanId: member.id }),
      })
      const data = await res.json().catch(() => ({}))
      setActionMsg(res.ok
        ? { ok: true, text: "Locked" }
        : { ok: false, text: data.error ?? `HTTP ${res.status}` })
      if (res.ok) router.refresh()
    } finally {
      setActing(false)
    }
  }

  async function resetCredentials() {
    if (!confirm(`Reset ${member.display_name}'s PIN + face? They'll get a setup link to choose new ones.`)) return
    setActing(true)
    setActionMsg(null)
    try {
      const res = await fetch("/api/admin/reset-credentials", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ targetHumanId: member.id }),
      })
      const data = await res.json().catch(() => ({}))
      if (res.ok) {
        setResetLink({ url: data.inviteUrl, name: data.targetDisplayName })
        setActionMsg({ ok: true, text: "Reset link generated — copy below" })
        router.refresh()
      } else {
        setActionMsg({ ok: false, text: data.error ?? `HTTP ${res.status}` })
      }
    } finally {
      setActing(false)
    }
  }

  async function unlockMember() {
    if (!confirm(`Unlock ${member.display_name}? Their existing PIN + face will work again.`)) return
    setActing(true)
    setActionMsg(null)
    try {
      const res = await fetch("/api/admin/unlock-user", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ targetHumanId: member.id }),
      })
      const data = await res.json().catch(() => ({}))
      setActionMsg(res.ok
        ? { ok: true, text: "Unlocked" }
        : { ok: false, text: data.error ?? `HTTP ${res.status}` })
      if (res.ok) router.refresh()
    } finally {
      setActing(false)
    }
  }

  async function clearFace() {
    if (!confirm(`Clear ${member.display_name}'s face data? They can keep using their PIN and upload a new face from Settings.`)) return
    setActing(true)
    setActionMsg(null)
    try {
      const res = await fetch("/api/admin/clear-face", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ targetHumanId: member.id }),
      })
      const data = await res.json().catch(() => ({}))
      setActionMsg(res.ok
        ? { ok: true, text: "Face data cleared" }
        : { ok: false, text: data.error ?? `HTTP ${res.status}` })
      if (res.ok) router.refresh()
    } finally {
      setActing(false)
    }
  }

  async function copyResetLink() {
    if (!resetLink) return
    await navigator.clipboard.writeText(resetLink.url)
    setLinkCopied(true)
    setTimeout(() => setLinkCopied(false), 2000)
  }

  async function resendInvite(rotate: boolean) {
    setActing(true)
    setActionMsg(null)
    try {
      const res = await fetch("/api/admin/resend-invite", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ targetHumanId: member.id, rotate }),
      })
      const data = await res.json().catch(() => ({}))
      if (res.ok) {
        setResetLink({ url: data.inviteUrl, name: data.targetDisplayName })
        const emailNote = data.email?.sent ? "Email re-sent." : `Email NOT sent (${data.email?.reason ?? "unknown"}). Copy the link below.`
        const rotateNote = data.rotated ? " Token rotated." : ""
        setActionMsg({ ok: true, text: `${emailNote}${rotateNote}` })
      } else {
        setActionMsg({ ok: false, text: data.error ?? `HTTP ${res.status}` })
      }
    } finally {
      setActing(false)
    }
  }

  async function confirmDelete() {
    setActing(true)
    setActionMsg(null)
    try {
      const res = await fetch("/api/admin/delete-human", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ targetHumanId: member.id, confirmDisplayName: deleteConfirmText }),
      })
      const data = await res.json().catch(() => ({}))
      if (res.ok) {
        setShowDelete(false)
        // Row is gone — bounce back to the list.
        router.push("/dashboard/humans")
      } else {
        setActionMsg({ ok: false, text: data.error ?? `HTTP ${res.status}` })
      }
    } finally {
      setActing(false)
    }
  }

  return (
    <>
      {/* Header */}
      <header className="flex items-start gap-5 mb-8">
        <UserAvatar name={member.display_name} src={member.avatar_url} size="xl" />
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-3 flex-wrap">
            <h1 className="text-2xl font-semibold tracking-tight text-foreground">{member.display_name}</h1>
            {member.is_owner && <Pill tone="accent">Owner</Pill>}
            <Pill tone={member.status === "active" ? "success" : "warning"}>{member.status}</Pill>
            {isSelf && <Pill tone="muted">You</Pill>}
          </div>
          <div className="flex items-center gap-3 mt-2 text-sm text-muted-foreground flex-wrap">
            {member.email && (
              <span className="flex items-center gap-1.5"><Mail size={13} /> {member.email}</span>
            )}
            {member.handle && <span>@{member.handle}</span>}
            <span className="flex items-center gap-1.5"><Shield size={13} /> {member.role}</span>
            <span className="flex items-center gap-1.5"><Calendar size={13} /> Joined {formatDate(member.created_at)}</span>
          </div>
        </div>
      </header>

      <Tabs
        active={tab}
        onChange={setTab}
        tabs={[
          { id: "profile", label: "Profile" },
          { id: "sessions", label: `Sessions (${sessions.length})` },
          { id: "activity", label: "Activity" },
        ]}
        className="mb-6"
      />

      {tab === "profile" && (
        <div className="space-y-4">
          <Card>
            <Section title="Identity" description="The fields they show up as around Nexus.">
              <dl className="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-3 mt-4">
                <Field label="Display name">{member.display_name}</Field>
                <Field label="Email">{member.email ?? "—"}</Field>
                <Field label="Handle">{member.handle ? "@" + member.handle : "—"}</Field>
                <Field label="Role">{member.role}{member.is_owner ? " (owner)" : ""}</Field>
                <Field label="Status">{member.status}</Field>
                <Field label="Avatar">{member.avatar_url ? "Uploaded" : "Initials fallback"}</Field>
              </dl>
            </Section>
          </Card>

          {canManage && !member.is_owner && !isSelf && (
            <Card tone="danger">
              <Section title="Admin actions" description="Resend invite re-emails an existing setup link without touching their PIN or face. Lock blocks sign-in; unlock restores. Reset PIN + face issues a brand-new invite link. Clear face keeps the PIN. Delete removes the human entirely.">
                <div className="flex flex-wrap gap-2 mt-4">
                  {member.status === "invited" && (
                    <>
                      <Button variant="secondary" size="sm" iconLeft={<Send size={13} />} onClick={() => resendInvite(false)} loading={acting}>
                        Resend invite email
                      </Button>
                      <Button variant="secondary" size="sm" iconLeft={<RotateCcw size={13} />} onClick={() => resendInvite(true)} loading={acting}>
                        Rotate + resend
                      </Button>
                    </>
                  )}
                  {member.status === "disabled" ? (
                    <Button variant="secondary" size="sm" iconLeft={<Unlock size={13} />} onClick={unlockMember} loading={acting}>
                      Unlock account
                    </Button>
                  ) : (
                    <Button variant="danger" size="sm" iconLeft={<Lock size={13} />} onClick={lockMember} loading={acting}>
                      Lock account
                    </Button>
                  )}
                  <Button variant="secondary" size="sm" iconLeft={<RotateCcw size={13} />} onClick={resetCredentials} loading={acting}>
                    Reset PIN + face
                  </Button>
                  <Button variant="secondary" size="sm" iconLeft={<ScanFace size={13} />} onClick={clearFace} loading={acting}>
                    Clear face only
                  </Button>
                  <Button variant="danger" size="sm" iconLeft={<Trash2 size={13} />} onClick={() => { setShowDelete(true); setDeleteConfirmText(""); setActionMsg(null) }} loading={acting}>
                    Delete user
                  </Button>
                </div>
                {actionMsg && (
                  <p className={`mt-3 text-sm ${actionMsg.ok ? "text-nexus-success" : "text-destructive"}`}>
                    {actionMsg.ok ? <CheckCircle2 size={14} className="inline mr-1.5" /> : <AlertTriangle size={14} className="inline mr-1.5" />}
                    {actionMsg.text}
                  </p>
                )}
                {resetLink && (
                  <div className="mt-4 flex items-center gap-2 p-3 rounded-xl bg-background border border-border">
                    <Link2 size={14} className="text-muted-foreground flex-shrink-0" />
                    <code className="flex-1 text-xs text-foreground/80 truncate font-mono">{resetLink.url}</code>
                    <button
                      type="button"
                      onClick={copyResetLink}
                      className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-primary/10 border border-primary/30 text-xs font-semibold text-primary hover:bg-primary/20 transition-all flex-shrink-0"
                    >
                      {linkCopied ? <><Check size={12} /> Copied!</> : <><Copy size={12} /> Copy</>}
                    </button>
                  </div>
                )}
              </Section>
            </Card>
          )}
        </div>
      )}

      {tab === "sessions" && (
        <Card padding="none">
          {sessions.length === 0 ? (
            <EmptyState icon={<Calendar size={28} />} title="No sessions" description="This member hasn't signed in yet, or all sessions have expired." />
          ) : (
            <ul className="divide-y divide-border">
              {sessions.map(s => (
                <li key={s.id} className="flex items-center gap-4 px-5 py-3.5">
                  <div className={`w-2 h-2 rounded-full flex-shrink-0 ${s.invalidated ? "bg-muted-foreground/40" : new Date(s.expires_at) < new Date() ? "bg-amber-400" : "bg-nexus-success"}`} />
                  <div className="flex-1 min-w-0">
                    <p className="text-sm text-foreground">{s.auth_method}</p>
                    <p className="text-xs text-muted-foreground mt-0.5">
                      Last verified {formatTime(s.last_verified_at)} · expires {formatDate(s.expires_at)}
                      {s.invalidated && " · invalidated"}
                    </p>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </Card>
      )}

      {tab === "activity" && (
        <div className="space-y-4">
          <Card padding="none">
            <Section title="Recent conversations" className="px-5 pt-5">
              {recentConversations.length === 0 ? (
                <EmptyState icon={<MessageSquare size={24} />} title="No conversations yet" />
              ) : (
                <ul className="divide-y divide-border">
                  {recentConversations.map(c => (
                    <li key={c.id} className="flex items-center justify-between gap-3 px-5 py-3 hover:bg-muted/40 transition-colors">
                      <span className="text-sm text-foreground truncate">{c.title || "Untitled"}</span>
                      <span className="text-xs text-muted-foreground flex-shrink-0">{timeAgo(c.updated_at)}</span>
                    </li>
                  ))}
                </ul>
              )}
            </Section>
          </Card>

          <Card padding="none">
            <Section title="Active operations" className="px-5 pt-5">
              {recentOperations.length === 0 ? (
                <EmptyState icon={<Workflow size={24} />} title="No operations yet" />
              ) : (
                <ul className="divide-y divide-border">
                  {recentOperations.map(o => (
                    <li key={o.id} className="flex items-center justify-between gap-3 px-5 py-3 hover:bg-muted/40 transition-colors">
                      <div className="flex items-center gap-2 min-w-0">
                        <span className="text-sm text-foreground truncate">{o.name}</span>
                        <Pill tone="muted" size="xs">{o.status}</Pill>
                        <Pill tone="muted" size="xs">{o.priority}</Pill>
                      </div>
                      <span className="text-xs text-muted-foreground flex-shrink-0">{timeAgo(o.updated_at)}</span>
                    </li>
                  ))}
                </ul>
              )}
            </Section>
          </Card>
        </div>
      )}

      {showDelete && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-sm p-4"
          onClick={() => !acting && setShowDelete(false)}
        >
          <div
            onClick={(e) => e.stopPropagation()}
            className="w-full max-w-md rounded-2xl bg-card border border-destructive/40 p-6 flex flex-col gap-4"
          >
            <div className="flex items-center justify-between">
              <h2 className="text-base font-bold text-destructive flex items-center gap-2">
                <Trash2 size={16} /> Delete {member.display_name}
              </h2>
              <button type="button" onClick={() => !acting && setShowDelete(false)} className="text-muted-foreground hover:text-foreground" aria-label="Close">
                <X size={16} />
              </button>
            </div>
            <p className="text-sm text-muted-foreground">
              This permanently removes the user, all active sessions, and registered push devices.
              Conversations and operations they touched stay in place. This cannot be undone.
            </p>
            <div>
              <label className="block text-xs font-medium text-foreground mb-1.5">
                Type <span className="font-mono text-destructive">{member.display_name}</span> to confirm
              </label>
              <input
                type="text"
                value={deleteConfirmText}
                onChange={(e) => setDeleteConfirmText(e.target.value)}
                autoFocus
                className="w-full px-3 py-2.5 rounded-lg bg-background border border-border text-sm focus:outline-none focus:border-destructive"
              />
            </div>
            {actionMsg && !actionMsg.ok && (
              <p className="text-xs text-destructive">
                <AlertTriangle size={12} className="inline mr-1" />
                {actionMsg.text}
              </p>
            )}
            <div className="flex gap-2">
              <button
                type="button"
                onClick={() => setShowDelete(false)}
                disabled={acting}
                className="flex-1 py-2.5 rounded-xl border border-border text-sm font-medium text-muted-foreground hover:text-foreground transition-all disabled:opacity-40"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={confirmDelete}
                disabled={acting || deleteConfirmText.trim().toLowerCase() !== member.display_name.trim().toLowerCase()}
                className="flex-1 py-2.5 rounded-xl bg-destructive text-destructive-foreground text-sm font-semibold hover:opacity-90 transition-all disabled:opacity-40 flex items-center justify-center gap-2"
              >
                {acting ? <Loader2 size={14} className="animate-spin" /> : <Trash2 size={14} />}
                Delete permanently
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  )
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-0.5">
      <dt className="text-xs text-muted-foreground">{label}</dt>
      <dd className="text-sm text-foreground">{children}</dd>
    </div>
  )
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" })
}

function formatTime(iso: string): string {
  return new Date(iso).toLocaleString("en-US", { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" })
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
