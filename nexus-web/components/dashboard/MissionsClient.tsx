"use client"

import { useState, useTransition } from "react"
import { addMission, deleteMission, updateMissionStatus } from "@/app/dashboard/missions/actions"

type Mission = {
  id: string
  name: string
  location: string
  status: string
  threat_level: string
  suit: string
  summary: string
  mission_date: string
  created_at: string
}

const STATUS_OPTS = ["SUCCESS", "FAILED", "ONGOING"]
const THREAT_OPTS = ["LOW", "MEDIUM", "HIGH", "CRITICAL"]
const SUIT_OPTS = ["Mark III", "Mark VII", "Mark XLII", "Mark L", "Mark LXXXV", "Hulkbuster", "Stealth", "Custom"]

const STATUS_COLOR: Record<string, string> = {
  SUCCESS: "text-green-400 border-green-400/40",
  FAILED: "text-hud-red border-[oklch(0.55_0.22_25/0.4)]",
  ONGOING: "text-yellow-400 border-yellow-400/40",
}
const THREAT_COLOR: Record<string, string> = {
  LOW: "text-green-400",
  MEDIUM: "text-yellow-400",
  HIGH: "text-orange-400",
  CRITICAL: "text-hud-red",
}

export default function MissionsClient({ initialMissions }: { initialMissions: Mission[] }) {
  const [showForm, setShowForm] = useState(false)
  const [filter, setFilter] = useState("ALL")
  const [expanded, setExpanded] = useState<string | null>(null)
  const [isPending, startTransition] = useTransition()

  const filtered = filter === "ALL" ? initialMissions : initialMissions.filter((m) => m.status === filter)

  function handleDelete(id: string) {
    if (!confirm("Delete this mission record?")) return
    startTransition(() => { deleteMission(id) })
  }

  function handleStatus(id: string, status: string) {
    startTransition(() => { updateMissionStatus(id, status) })
  }

  return (
    <div className="p-8 scan-line min-h-screen">
      <div className="flex items-center justify-between mb-8">
        <div>
          <p className="font-mono text-xs text-muted-foreground mb-1" style={{ fontFamily: "var(--font-orbitron)" }}>{">"} OPERATIONS LOG</p>
          <h1 className="text-2xl font-bold text-hud-gold tracking-widest" style={{ fontFamily: "var(--font-orbitron)" }}>MISSION CONTROL</h1>
        </div>
        <button
          onClick={() => setShowForm(!showForm)}
          className="hud-border hud-glow-red px-5 py-2.5 font-mono text-xs text-hud-red hover:bg-[oklch(0.55_0.22_25/0.15)] transition-all"
          style={{ fontFamily: "var(--font-orbitron)" }}
        >
          {showForm ? "CANCEL" : "+ LOG MISSION"}
        </button>
      </div>

      {/* Add Mission Form */}
      {showForm && (
        <form
          action={async (fd) => {
            await addMission(fd)
            setShowForm(false)
          }}
          className="hud-border bg-card p-6 mb-6"
        >
          <h2 className="font-mono text-xs text-hud-gold tracking-widest mb-5" style={{ fontFamily: "var(--font-orbitron)" }}>NEW MISSION RECORD</h2>
          <div className="grid grid-cols-2 gap-4 mb-4">
            <div>
              <label className="font-mono text-[10px] text-muted-foreground block mb-1.5" style={{ fontFamily: "var(--font-orbitron)" }}>MISSION NAME *</label>
              <input name="name" required className="w-full bg-muted hud-border px-3 py-2 font-mono text-sm text-foreground focus:outline-none focus:border-[oklch(0.55_0.22_25/0.8)]" placeholder="Operation..." />
            </div>
            <div>
              <label className="font-mono text-[10px] text-muted-foreground block mb-1.5" style={{ fontFamily: "var(--font-orbitron)" }}>LOCATION *</label>
              <input name="location" required className="w-full bg-muted hud-border px-3 py-2 font-mono text-sm text-foreground focus:outline-none focus:border-[oklch(0.55_0.22_25/0.8)]" placeholder="City, Country..." />
            </div>
            <div>
              <label className="font-mono text-[10px] text-muted-foreground block mb-1.5" style={{ fontFamily: "var(--font-orbitron)" }}>STATUS *</label>
              <select name="status" required className="w-full bg-muted hud-border px-3 py-2 font-mono text-sm text-foreground focus:outline-none">
                {STATUS_OPTS.map((s) => <option key={s} value={s}>{s}</option>)}
              </select>
            </div>
            <div>
              <label className="font-mono text-[10px] text-muted-foreground block mb-1.5" style={{ fontFamily: "var(--font-orbitron)" }}>THREAT LEVEL *</label>
              <select name="threat_level" required className="w-full bg-muted hud-border px-3 py-2 font-mono text-sm text-foreground focus:outline-none">
                {THREAT_OPTS.map((t) => <option key={t} value={t}>{t}</option>)}
              </select>
            </div>
            <div>
              <label className="font-mono text-[10px] text-muted-foreground block mb-1.5" style={{ fontFamily: "var(--font-orbitron)" }}>SUIT DEPLOYED *</label>
              <select name="suit" required className="w-full bg-muted hud-border px-3 py-2 font-mono text-sm text-foreground focus:outline-none">
                {SUIT_OPTS.map((s) => <option key={s} value={s}>{s}</option>)}
              </select>
            </div>
          </div>
          <div className="mb-4">
            <label className="font-mono text-[10px] text-muted-foreground block mb-1.5" style={{ fontFamily: "var(--font-orbitron)" }}>MISSION SUMMARY *</label>
            <textarea name="summary" required rows={3} className="w-full bg-muted hud-border px-3 py-2 font-mono text-sm text-foreground focus:outline-none focus:border-[oklch(0.55_0.22_25/0.8)] resize-none" placeholder="Brief operational summary..." />
          </div>
          <button type="submit" disabled={isPending} className="hud-border hud-glow-gold px-6 py-2.5 font-mono text-xs text-hud-gold hover:bg-[oklch(0.75_0.18_75/0.15)] transition-all disabled:opacity-50" style={{ fontFamily: "var(--font-orbitron)" }}>
            {isPending ? "SAVING..." : "COMMIT TO DATABASE"}
          </button>
        </form>
      )}

      {/* Filter Tabs */}
      <div className="flex items-center gap-2 mb-5">
        {["ALL", ...STATUS_OPTS].map((f) => (
          <button
            key={f}
            onClick={() => setFilter(f)}
            className={`font-mono text-[10px] px-3 py-1.5 transition-all ${filter === f ? "hud-border text-hud-gold" : "text-muted-foreground hover:text-hud-gold"}`}
            style={{ fontFamily: "var(--font-orbitron)" }}
          >
            {f}
          </button>
        ))}
        <span className="font-mono text-[10px] text-muted-foreground ml-auto">{filtered.length} RECORDS</span>
      </div>

      {/* Missions List */}
      {filtered.length === 0 ? (
        <div className="hud-border bg-card p-12 text-center">
          <p className="font-mono text-sm text-muted-foreground">No mission records found.</p>
          <p className="font-mono text-xs text-muted-foreground mt-2">Click &quot;+ LOG MISSION&quot; to add your first operation.</p>
        </div>
      ) : (
        <div className="flex flex-col gap-3">
          {filtered.map((m) => (
            <div key={m.id} className="hud-border bg-card">
              <div
                className="flex items-center justify-between p-4 cursor-pointer hover:bg-[oklch(0.55_0.22_25/0.03)] transition-colors"
                onClick={() => setExpanded(expanded === m.id ? null : m.id)}
              >
                <div className="flex items-center gap-4">
                  <span className={`font-mono text-[10px] border px-2 py-0.5 ${STATUS_COLOR[m.status]}`} style={{ fontFamily: "var(--font-orbitron)" }}>{m.status}</span>
                  <div>
                    <p className="font-mono text-sm text-foreground">{m.name}</p>
                    <p className="font-mono text-[10px] text-muted-foreground">{m.location} · {m.suit}</p>
                  </div>
                </div>
                <div className="flex items-center gap-4">
                  <span className={`font-mono text-[10px] ${THREAT_COLOR[m.threat_level]}`}>{m.threat_level}</span>
                  <span className="font-mono text-[10px] text-muted-foreground">{new Date(m.mission_date).toLocaleDateString()}</span>
                  <span className="text-muted-foreground font-mono text-xs">{expanded === m.id ? "▲" : "▼"}</span>
                </div>
              </div>
              {expanded === m.id && (
                <div className="border-t border-border p-4">
                  <p className="font-mono text-xs text-muted-foreground mb-4">{m.summary}</p>
                  <div className="flex items-center gap-3 flex-wrap">
                    <span className="font-mono text-[10px] text-muted-foreground" style={{ fontFamily: "var(--font-orbitron)" }}>UPDATE STATUS:</span>
                    {STATUS_OPTS.filter((s) => s !== m.status).map((s) => (
                      <button key={s} onClick={() => handleStatus(m.id, s)} disabled={isPending}
                        className={`font-mono text-[10px] border px-3 py-1 transition-all hover:bg-[oklch(0.55_0.22_25/0.1)] disabled:opacity-50 ${STATUS_COLOR[s]}`}
                        style={{ fontFamily: "var(--font-orbitron)" }}
                      >{s}</button>
                    ))}
                    <button onClick={() => handleDelete(m.id)} disabled={isPending}
                      className="font-mono text-[10px] text-hud-red hud-border px-3 py-1 hover:bg-[oklch(0.55_0.22_25/0.1)] transition-all ml-auto disabled:opacity-50"
                      style={{ fontFamily: "var(--font-orbitron)" }}
                    >DELETE</button>
                  </div>
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
