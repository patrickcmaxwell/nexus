"use client"

import { useState } from "react"

const SUITS = [
  { id: 1, name: "Mark III", status: "ACTIVE", type: "Combat", power: 92, armor: 88, speed: 78, weapons: ["Repulsors", "Missiles", "Uni-beam"], special: "First full combat-capable suit", color: "text-hud-red" },
  { id: 2, name: "Mark VII", status: "ACTIVE", type: "Combat", power: 96, armor: 91, speed: 85, weapons: ["Repulsors", "Missiles", "Laser", "Uni-beam"], special: "Autonomous deployment system", color: "text-hud-gold" },
  { id: 3, name: "Mark XLII", status: "ACTIVE", type: "Modular", power: 94, armor: 87, speed: 90, weapons: ["Repulsors", "Uni-beam", "Adaptive systems"], special: "Autonomous targeting — responds to neural commands", color: "text-hud-red" },
  { id: 4, name: "Hulkbuster", status: "RESERVE", type: "Heavy", power: 99, armor: 99, speed: 40, weapons: ["Pile driver fists", "Reinforced repulsors", "Containment foam"], special: "Anti-Hulk protocol — requires Mark XLIV core", color: "text-orange-400" },
  { id: 5, name: "Mark L", status: "ACTIVE", type: "Nano", power: 98, armor: 95, speed: 96, weapons: ["Nano-repulsors", "Blade system", "Energy shield", "Missile clusters"], special: "Nanotechnology — instant deployment from arc reactor", color: "text-hud-gold" },
  { id: 6, name: "Mark LXXXV", status: "ACTIVE", type: "Nano", power: 100, armor: 98, speed: 98, weapons: ["Nano-repulsors", "Time Stone compatible", "Full armament suite"], special: "Most advanced suit — nanotechnology with quantum capability", color: "text-hud-gold" },
  { id: 7, name: "Stealth Suit", status: "RESERVE", type: "Stealth", power: 80, armor: 72, speed: 94, weapons: ["Silenced repulsors", "EMP", "Targeted strike"], special: "Full radar/thermal invisibility", color: "text-blue-400" },
  { id: 8, name: "Iron Patriot", status: "ARCHIVED", type: "Combat", power: 88, armor: 90, speed: 82, weapons: ["Repulsors", "Machine guns", "Missiles"], special: "Military-grade variant — joint ops clearance", color: "text-muted-foreground" },
]

function Bar({ value, color }: { value: number; color: string }) {
  return (
    <div className="h-1.5 bg-muted w-full rounded-sm overflow-hidden">
      <div className={`h-full rounded-sm transition-all duration-500 ${color}`} style={{ width: `${value}%` }} />
    </div>
  )
}

export default function SuitsPage() {
  const [selected, setSelected] = useState<typeof SUITS[0] | null>(null)

  const STATUS_COLOR: Record<string, string> = {
    ACTIVE: "text-green-400 border-green-400/30",
    RESERVE: "text-yellow-400 border-yellow-400/30",
    ARCHIVED: "text-muted-foreground border-border",
  }

  return (
    <div className="p-8 scan-line min-h-screen">
      <div className="mb-8">
        <p className="font-mono text-xs text-muted-foreground mb-1" style={{ fontFamily: "var(--font-orbitron)" }}>{">"} ARMOR DIVISION</p>
        <h1 className="text-2xl font-bold text-hud-gold tracking-widest" style={{ fontFamily: "var(--font-orbitron)" }}>SUIT REGISTRY</h1>
        <p className="font-mono text-xs text-muted-foreground mt-1">{SUITS.filter(s => s.status === "ACTIVE").length} active · {SUITS.filter(s => s.status === "RESERVE").length} reserve · {SUITS.filter(s => s.status === "ARCHIVED").length} archived</p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        {SUITS.map((suit) => (
          <div
            key={suit.id}
            onClick={() => setSelected(selected?.id === suit.id ? null : suit)}
            className="hud-border bg-card p-5 cursor-pointer hover:border-[oklch(0.55_0.22_25/0.7)] transition-all"
          >
            <div className="flex items-start justify-between mb-4">
              <div>
                <h2 className="font-bold text-foreground" style={{ fontFamily: "var(--font-orbitron)" }}>{suit.name}</h2>
                <p className="font-mono text-[10px] text-muted-foreground">{suit.type.toUpperCase()} CLASS</p>
              </div>
              <span className={`font-mono text-[10px] border px-2 py-0.5 ${STATUS_COLOR[suit.status]}`} style={{ fontFamily: "var(--font-orbitron)" }}>
                {suit.status}
              </span>
            </div>

            <div className="flex flex-col gap-2 mb-4">
              {[["POWER", suit.power, "bg-hud-red"], ["ARMOR", suit.armor, "bg-hud-gold"], ["SPEED", suit.speed, "bg-blue-400"]].map(([label, val, col]) => (
                <div key={label as string} className="flex items-center gap-3">
                  <span className="font-mono text-[10px] text-muted-foreground w-12" style={{ fontFamily: "var(--font-orbitron)" }}>{label}</span>
                  <div className="flex-1"><Bar value={val as number} color={col as string} /></div>
                  <span className="font-mono text-[10px] text-muted-foreground w-8 text-right">{val}%</span>
                </div>
              ))}
            </div>

            {selected?.id === suit.id && (
              <div className="border-t border-border pt-4">
                <p className="font-mono text-[10px] text-hud-gold mb-2" style={{ fontFamily: "var(--font-orbitron)" }}>WEAPONS SYSTEMS</p>
                <div className="flex flex-wrap gap-2 mb-3">
                  {suit.weapons.map((w) => (
                    <span key={w} className="font-mono text-[10px] hud-border px-2 py-1 text-muted-foreground">{w}</span>
                  ))}
                </div>
                <p className="font-mono text-[10px] text-hud-gold mb-1" style={{ fontFamily: "var(--font-orbitron)" }}>SPECIAL CAPABILITY</p>
                <p className="font-mono text-xs text-muted-foreground">{suit.special}</p>
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  )
}
