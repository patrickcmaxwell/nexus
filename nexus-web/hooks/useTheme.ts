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

function getSystemDark() {
  if (typeof window === "undefined") return true
  return window.matchMedia("(prefers-color-scheme: dark)").matches
}

function loadPrefs(): ThemePreference {
  if (typeof window === "undefined") return { colorMode: "system", uiMode: "futuristic" }
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (raw) return { colorMode: "system", uiMode: "futuristic", ...JSON.parse(raw) }
  } catch { /* ignore */ }
  return { colorMode: "system", uiMode: "futuristic" }
}

function resolveTheme(prefs: ThemePreference): ResolvedTheme {
  const isDark = prefs.colorMode === "system" ? getSystemDark() : prefs.colorMode === "dark"
  return {
    isDark,
    isSimple: prefs.uiMode === "simple",
    isFuturistic: prefs.uiMode === "futuristic",
  }
}

function applyTheme(prefs: ThemePreference) {
  const html = document.documentElement
  const resolved = resolveTheme(prefs)

  // Color mode
  if (resolved.isDark) {
    html.classList.remove("light")
    html.classList.add("dark")
  } else {
    html.classList.add("light")
    html.classList.remove("dark")
  }

  // UI mode
  html.setAttribute("data-ui", prefs.uiMode)
}

export function useTheme() {
  const [prefs, setPrefs] = useState<ThemePreference>({ colorMode: "system", uiMode: "futuristic" })
  const [resolved, setResolved] = useState<ResolvedTheme>({ isDark: true, isSimple: false, isFuturistic: true })

  // Load on mount
  useEffect(() => {
    const loaded = loadPrefs()
    setPrefs(loaded)
    setResolved(resolveTheme(loaded))
    applyTheme(loaded)

    // Watch system preference changes
    const mq = window.matchMedia("(prefers-color-scheme: dark)")
    const handler = () => {
      const current = loadPrefs()
      if (current.colorMode === "system") {
        applyTheme(current)
        setResolved(resolveTheme(current))
      }
    }
    mq.addEventListener("change", handler)
    return () => mq.removeEventListener("change", handler)
  }, [])

  const update = useCallback((next: Partial<ThemePreference>) => {
    setPrefs(prev => {
      const merged = { ...prev, ...next }
      localStorage.setItem(STORAGE_KEY, JSON.stringify(merged))
      applyTheme(merged)
      setResolved(resolveTheme(merged))
      return merged
    })
  }, [])

  return { prefs, update, resolved }
}
