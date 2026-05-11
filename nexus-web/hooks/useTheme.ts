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

// 2026-05-08: BOTH colorMode and uiMode are locked.
//   - colorMode = "dark" — light mode has too many hardcoded dark-only inline
//     styles to be usable; revisit after inline-style sweep
//   - uiMode    = "simple" — the futuristic Tron/HUD aesthetic was rejected
//     in favor of an Apple/Linear-style clean baseline. Simple is now the
//     ONE consistent design across all pages.

function loadPrefs(): ThemePreference {
  // Locked. Stored prefs ignored.
  return { colorMode: "dark", uiMode: "simple" }
}

function resolveTheme(_prefs: ThemePreference): ResolvedTheme {
  return {
    isDark: true,
    isSimple: true,
    isFuturistic: false,
  }
}

function applyTheme(_prefs: ThemePreference) {
  const html = document.documentElement
  html.classList.remove("light")
  html.classList.add("dark")
  html.setAttribute("data-ui", "simple")
}

export function useTheme() {
  // Locked theme — both color and UI modes are fixed for now. All
  // consumers get the same resolved values. `update` is a no-op so any
  // legacy theme-toggle calls don't crash.
  const [prefs] = useState<ThemePreference>({ colorMode: "dark", uiMode: "simple" })
  const [resolved] = useState<ResolvedTheme>({ isDark: true, isSimple: true, isFuturistic: false })

  useEffect(() => {
    applyTheme(prefs)
  }, [prefs])

  const update = useCallback((_next: Partial<ThemePreference>) => {
    // No-op. Theme is locked.
  }, [])

  return { prefs, update, resolved }
}
