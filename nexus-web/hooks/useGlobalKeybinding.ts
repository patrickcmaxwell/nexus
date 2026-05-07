"use client"

import { useEffect } from "react"

// useGlobalKeybinding
//
// Tiny hook for registering a keyboard shortcut at the window level. Used
// by the SearchPalette to bind Cmd/Ctrl-K from any dashboard page.
//
// Pass the keys (lowercase letter or special key name) and modifier flags;
// the handler fires when the combo matches AND we're not inside a text input
// (so users typing in a chat composer don't accidentally open the palette).

type Modifiers = {
  meta?: boolean   // Cmd on macOS
  ctrl?: boolean   // Ctrl on Win/Linux
  shift?: boolean
  alt?: boolean
}

export function useGlobalKeybinding(
  key: string,
  modifiers: Modifiers,
  handler: () => void,
  deps: ReadonlyArray<unknown> = []
): void {
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      // Match accelerator. We accept "either meta or ctrl" via the macOS
      // convention: if caller specified meta, allow ctrl too on non-Mac so
      // Linux/Windows users get the same binding.
      const wantsCmd = modifiers.meta === true
      const cmdHit = wantsCmd ? (e.metaKey || e.ctrlKey) : true
      if (modifiers.meta === false && (e.metaKey || e.ctrlKey)) return
      if (modifiers.shift === true && !e.shiftKey) return
      if (modifiers.shift === false && e.shiftKey) return
      if (modifiers.alt === true && !e.altKey) return
      if (modifiers.alt === false && e.altKey) return
      if (!cmdHit) return
      if (e.key.toLowerCase() !== key.toLowerCase()) return

      // Don't fire when the user is typing in a text field — they probably
      // meant the literal keystroke. Exception: explicit Cmd-K is unambiguous
      // even mid-type, so we let it through.
      const target = e.target as HTMLElement | null
      const inText = target?.tagName === "INPUT" || target?.tagName === "TEXTAREA" || target?.isContentEditable
      const isExplicitOverride = wantsCmd  // Cmd combos are intentional
      if (inText && !isExplicitOverride) return

      e.preventDefault()
      handler()
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps)
}
