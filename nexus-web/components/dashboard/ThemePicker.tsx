"use client"

import { Sun, Moon, Monitor, Zap, LayoutDashboard, Check } from "lucide-react"
import { useTheme, type ColorMode, type UIMode } from "@/hooks/useTheme"

export default function ThemePicker() {
  const { prefs, update } = useTheme()

  const colorOptions: { value: ColorMode; label: string; icon: React.ReactNode }[] = [
    { value: "light", label: "Light", icon: <Sun size={16} /> },
    { value: "dark",  label: "Dark",  icon: <Moon size={16} /> },
    { value: "system", label: "System", icon: <Monitor size={16} /> },
  ]

  const uiOptions: { value: UIMode; label: string; desc: string; icon: React.ReactNode }[] = [
    { value: "futuristic", label: "Futuristic", desc: "Iron Man HUD with glows and grids", icon: <Zap size={16} /> },
    { value: "simple", label: "Simple", desc: "Apple-style clean and minimal", icon: <LayoutDashboard size={16} /> },
  ]

  return (
    <div className="space-y-5">
      {/* UI Mode */}
      <div>
        <p className="text-xs font-bold uppercase tracking-widest text-foreground/40 mb-3">Style</p>
        <div className="flex flex-col gap-2">
          {uiOptions.map(opt => (
            <button
              key={opt.value}
              onClick={() => update({ uiMode: opt.value })}
              className={`flex items-center gap-3 w-full px-3 py-2.5 rounded-xl border text-left transition-all duration-200 ${
                prefs.uiMode === opt.value
                  ? "border-nexus-cyan/60 bg-nexus-cyan/10 text-foreground"
                  : "border-border bg-card text-foreground/60 hover:text-foreground hover:border-foreground/20"
              }`}
            >
              <span className={prefs.uiMode === opt.value ? "text-nexus-cyan" : "text-foreground/40"}>
                {opt.icon}
              </span>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-semibold leading-none">{opt.label}</p>
                <p className="text-xs text-foreground/40 mt-0.5">{opt.desc}</p>
              </div>
              {prefs.uiMode === opt.value && (
                <Check size={14} className="text-nexus-cyan flex-shrink-0" />
              )}
            </button>
          ))}
        </div>
      </div>

      {/* Color Mode */}
      <div>
        <p className="text-xs font-bold uppercase tracking-widest text-foreground/40 mb-3">Color</p>
        <div className="flex gap-2">
          {colorOptions.map(opt => (
            <button
              key={opt.value}
              onClick={() => update({ colorMode: opt.value })}
              className={`flex-1 flex flex-col items-center gap-1.5 py-2.5 rounded-xl border text-xs font-semibold transition-all duration-200 ${
                prefs.colorMode === opt.value
                  ? "border-nexus-cyan/60 bg-nexus-cyan/10 text-nexus-cyan"
                  : "border-border bg-card text-foreground/50 hover:text-foreground hover:border-foreground/20"
              }`}
            >
              {opt.icon}
              {opt.label}
            </button>
          ))}
        </div>
      </div>
    </div>
  )
}
