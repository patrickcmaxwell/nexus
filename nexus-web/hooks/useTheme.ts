"use client"

import { useCallback, useEffect, useState, createContext, useContext } from "react"

export type ColorMode = "light" | "dark" | "system"
export type UIMode = "simple" | "futuristic"

export type ThemePreference = {
  colorMode: ColorMode
  uiMode: UIMode
}

export type ResolvedTheme = {
  isDark: boolean
  isSimple: boolean
  isFuturistic: boolean
}

const STORAGE_KEY = "nexus_theme"

// Color mode is locked to "dark" globally as of 2026-05-08. The light theme
// has hardcoded dark-only inline styles in too many components — until those
// are migrated to theme tokens, light mode produces broken contrast (cyan on
// near-black inside white containers). Re-enable when the inline-style sweep
// is done. uiMode (simple vs futuristic) is still user-controllable.

function loadPrefs(): ThemePreference {
  if (typeof window === "undefined") return { colorMode: "dark", uiMode: "futuristic" }
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (raw) {
      const stored = JSON.parse(raw) as Partial<ThemePreference>
      return { colorMode: "dark", uiMode: stored.uiMode ?? "futuristic" }
    }
  } catch { /* ignore */ }
  return { colorMode: "dark", uiMode: "futuristic" }
}

function resolveTheme(prefs: ThemePreference): ResolvedTheme {
  // Always dark for now — see note above.
  return {
    isDark: true,
    isSimple: prefs.uiMode === "simple",
    isFuturistic: prefs.uiMode === "futuristic",
  }
}

function applyTheme(prefs: ThemePreference) {
  const html = document.documentElement
  // Always dark.
  html.classList.remove("light")
  html.classList.add("dark")
  html.setAttribute("data-ui", prefs.uiMode)
}

export function useTheme() {
  const [prefs, setPrefs] = useState<ThemePreference>({ colorMode: "dark", uiMode: "futuristic" })
  const [resolved, setResolved] = useState<ResolvedTheme>({ isDark: true, isSimple: false, isFuturistic: true })

  // Load on mount
  useEffect(() => {
    const loaded = loadPrefs()
    setPrefs(loaded)
    setResolved(resolveTheme(loaded))
    applyTheme(loaded)
  }, [])

  const update = useCallback((next: Partial<ThemePreference>) => {
    setPrefs(prev => {
      // colorMode is locked to dark — silently drop any colorMode change.
      const merged = { ...prev, ...next, colorMode: "dark" as const }
      localStorage.setItem(STORAGE_KEY, JSON.stringify(merged))
      applyTheme(merged)
      setResolved(resolveTheme(merged))
      return merged
    })
  }, [])

  return { prefs, update, resolved }
}
