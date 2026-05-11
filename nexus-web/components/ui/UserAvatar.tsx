// UserAvatar — single source of truth for rendering a human's face/identity
// across the app. Apple/Linear-style: round, soft border, smart fallback to
// colored initials when no upload exists.
//
// Use everywhere a person appears:
//   - Sidebar footer
//   - Settings identity card
//   - Humans list rows
//   - Maxwell chat next to messages
//   - Mention chips
//   - Invite emails (TODO)
//
// Don't render <img> directly anymore — go through this so the fallback,
// alt text, and sizing stay consistent.

import React from "react"

type Size = "xs" | "sm" | "md" | "lg" | "xl"

const SIZE_CLASSES: Record<Size, string> = {
  xs: "w-5 h-5 text-[10px]",
  sm: "w-7 h-7 text-xs",
  md: "w-9 h-9 text-sm",
  lg: "w-12 h-12 text-base",
  xl: "w-20 h-20 text-2xl",
}

// Deterministic color from a string. Same name → always same color.
// Uses a small palette of restrained, on-brand tints.
const COLORS = [
  { bg: "oklch(0.30 0.10 250)", fg: "oklch(0.92 0.05 250)" },  // blue
  { bg: "oklch(0.30 0.10 180)", fg: "oklch(0.92 0.05 180)" },  // teal
  { bg: "oklch(0.30 0.10 145)", fg: "oklch(0.92 0.05 145)" },  // green
  { bg: "oklch(0.30 0.10 80)",  fg: "oklch(0.92 0.05 80)" },   // amber
  { bg: "oklch(0.30 0.10 25)",  fg: "oklch(0.92 0.05 25)" },   // rose
  { bg: "oklch(0.30 0.10 320)", fg: "oklch(0.92 0.05 320)" },  // pink
  { bg: "oklch(0.30 0.10 285)", fg: "oklch(0.92 0.05 285)" },  // violet
]

function colorFor(seed: string): { bg: string; fg: string } {
  if (!seed) return COLORS[0]
  let hash = 0
  for (let i = 0; i < seed.length; i++) {
    hash = (hash << 5) - hash + seed.charCodeAt(i)
    hash |= 0
  }
  return COLORS[Math.abs(hash) % COLORS.length]
}

function initials(name: string): string {
  if (!name) return "?"
  const parts = name.trim().split(/\s+/).slice(0, 2)
  return parts.map(p => p[0] || "").join("").toUpperCase() || "?"
}

export type UserAvatarProps = {
  /** Display name — used for initials fallback + alt text + color seed. */
  name: string
  /** Public URL of the avatar image, or null/undefined for fallback. */
  src?: string | null
  size?: Size
  /** Optional ring (Apple-style "online" or "active" indicator). */
  ring?: "none" | "primary" | "muted"
  /** Extra Tailwind classes. */
  className?: string
}

export function UserAvatar({
  name, src, size = "md", ring = "muted", className = "",
}: UserAvatarProps) {
  const sizeClass = SIZE_CLASSES[size]
  const ringClass = ring === "primary" ? "ring-2 ring-primary/40 ring-offset-2 ring-offset-background"
                  : ring === "muted"   ? "ring-1 ring-border"
                  : ""

  if (src) {
    return (
      // eslint-disable-next-line @next/next/no-img-element
      <img
        src={src}
        alt={name || "avatar"}
        className={`${sizeClass} ${ringClass} rounded-full object-cover flex-shrink-0 ${className}`}
      />
    )
  }

  const c = colorFor(name)
  return (
    <div
      role="img"
      aria-label={name || "avatar"}
      title={name}
      className={`${sizeClass} ${ringClass} rounded-full flex items-center justify-center font-semibold flex-shrink-0 ${className}`}
      style={{ background: c.bg, color: c.fg }}
    >
      {initials(name)}
    </div>
  )
}

// Eve's special avatar — gradient orb. Used wherever Eve speaks.
export function EveAvatar({ size = "md", className = "" }: { size?: Size; className?: string }) {
  const sizeClass = SIZE_CLASSES[size]
  return (
    <div
      role="img"
      aria-label="Eve"
      title="Eve"
      className={`${sizeClass} rounded-full flex items-center justify-center flex-shrink-0 ${className}`}
      style={{
        background: "radial-gradient(circle at 30% 30%, oklch(0.78 0.18 250), oklch(0.30 0.18 250))",
        boxShadow: "inset 0 1px 1px oklch(1 0 0 / 0.2)",
      }}
    >
      <span className="font-semibold text-white text-[0.7em]">E</span>
    </div>
  )
}
