// Design system primitives. Compose pages from these — don't reach for raw
// Tailwind classes for cards/buttons/inputs/pills anymore. The point is
// consistency: every page that renders a Card, Button, Pill, Input, etc.,
// gets the same surface treatment, the same hover state, the same rhythm.
//
// Reference points: Linear, Vercel dashboard, Stripe dashboard, Notion.
// Restrained, dense, generous whitespace, single accent.

"use client"

import { forwardRef, ComponentProps, HTMLAttributes } from "react"
import { Loader2 } from "lucide-react"

// ─── Card ────────────────────────────────────────────────────────────────────
//
// Soft surface with hairline border. The base for almost every container.
// `interactive` adds hover affordance (border lifts, slight bg shift).
// `tone` lets a card pick up an accent color for emphasis (success / warning
// / danger / accent) — used sparingly.

type CardProps = HTMLAttributes<HTMLDivElement> & {
  interactive?: boolean
  tone?: "default" | "accent" | "success" | "warning" | "danger"
  padding?: "none" | "sm" | "md" | "lg"
}

const CARD_PADDING: Record<NonNullable<CardProps["padding"]>, string> = {
  none: "",
  sm:   "p-4",
  md:   "p-5 md:p-6",
  lg:   "p-6 md:p-8",
}

const CARD_TONE: Record<NonNullable<CardProps["tone"]>, string> = {
  default: "bg-card border-border",
  accent:  "bg-primary/5 border-primary/30",
  success: "bg-nexus-success/5 border-nexus-success/30",
  warning: "bg-nexus-warning/5 border-nexus-warning/30",
  danger:  "bg-destructive/5 border-destructive/30",
}

export function Card({
  interactive = false,
  tone = "default",
  padding = "md",
  className = "",
  ...rest
}: CardProps) {
  const interactiveClasses = interactive
    ? "transition-colors hover:border-border/80 cursor-pointer"
    : ""
  return (
    <div
      className={`rounded-xl border ${CARD_TONE[tone]} ${CARD_PADDING[padding]} ${interactiveClasses} ${className}`}
      {...rest}
    />
  )
}

// ─── Button ──────────────────────────────────────────────────────────────────
//
// Five variants. All same height by size. Primary uses the brand accent;
// secondary is a quiet outline; ghost is borderless; danger is destructive;
// link reads like a hyperlink.

type ButtonVariant = "primary" | "secondary" | "ghost" | "danger" | "link"
type ButtonSize = "sm" | "md" | "lg"

type ButtonProps = ComponentProps<"button"> & {
  variant?: ButtonVariant
  size?: ButtonSize
  loading?: boolean
  iconLeft?: React.ReactNode
  iconRight?: React.ReactNode
  fullWidth?: boolean
}

const BUTTON_SIZES: Record<ButtonSize, string> = {
  sm: "h-8 px-3 text-xs gap-1.5 rounded-md",
  md: "h-9 px-4 text-sm gap-2 rounded-lg",
  lg: "h-11 px-5 text-sm gap-2 rounded-lg",
}

const BUTTON_VARIANTS: Record<ButtonVariant, string> = {
  primary:   "bg-primary text-primary-foreground hover:opacity-90 active:opacity-80",
  secondary: "bg-card border border-border text-foreground hover:bg-muted hover:border-border/80",
  ghost:     "text-muted-foreground hover:text-foreground hover:bg-muted",
  danger:    "text-destructive hover:bg-destructive/10",
  link:      "text-primary underline-offset-4 hover:underline px-0 h-auto",
}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(function Button(
  { variant = "secondary", size = "md", loading, iconLeft, iconRight, fullWidth, className = "", children, disabled, ...rest },
  ref,
) {
  const widthClass = fullWidth ? "w-full" : ""
  return (
    <button
      ref={ref}
      disabled={disabled || loading}
      className={`inline-flex items-center justify-center font-medium tracking-tight transition-all disabled:opacity-40 disabled:cursor-not-allowed ${BUTTON_SIZES[size]} ${BUTTON_VARIANTS[variant]} ${widthClass} ${className}`}
      {...rest}
    >
      {loading ? <Loader2 className="animate-spin" size={size === "lg" ? 16 : 14} /> : iconLeft}
      {children}
      {iconRight}
    </button>
  )
})

// ─── Input ───────────────────────────────────────────────────────────────────

type InputProps = ComponentProps<"input">

export const Input = forwardRef<HTMLInputElement, InputProps>(function Input(
  { className = "", ...rest }, ref,
) {
  return (
    <input
      ref={ref}
      className={`w-full h-9 px-3 rounded-lg bg-background border border-border text-sm text-foreground placeholder:text-muted-foreground/60 focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20 transition-colors ${className}`}
      {...rest}
    />
  )
})

// ─── Pill ────────────────────────────────────────────────────────────────────
//
// Status / label / count badge. Quiet by default; tone bumps emphasis.

type PillTone = "neutral" | "accent" | "success" | "warning" | "danger" | "muted"
type PillSize = "xs" | "sm"

type PillProps = HTMLAttributes<HTMLSpanElement> & {
  tone?: PillTone
  size?: PillSize
}

const PILL_TONES: Record<PillTone, string> = {
  neutral: "bg-muted text-foreground",
  accent:  "bg-primary/15 text-primary",
  success: "bg-nexus-success/15 text-nexus-success",
  warning: "bg-nexus-warning/15 text-nexus-warning",
  danger:  "bg-destructive/15 text-destructive",
  muted:   "bg-transparent text-muted-foreground border border-border",
}

const PILL_SIZES: Record<PillSize, string> = {
  xs: "text-[10px] px-1.5 py-0.5 rounded",
  sm: "text-xs px-2 py-0.5 rounded-md",
}

export function Pill({
  tone = "neutral",
  size = "sm",
  className = "",
  ...rest
}: PillProps) {
  return (
    <span
      className={`inline-flex items-center gap-1 font-medium ${PILL_TONES[tone]} ${PILL_SIZES[size]} ${className}`}
      {...rest}
    />
  )
}

// ─── Section ─────────────────────────────────────────────────────────────────
//
// A page-level grouping with title + optional action. Used by widgets so
// their headers render the same way everywhere.

type SectionProps = HTMLAttributes<HTMLDivElement> & {
  title?: string
  description?: string
  action?: React.ReactNode
}

export function Section({ title, description, action, children, className = "", ...rest }: SectionProps) {
  return (
    <section className={`flex flex-col gap-3 ${className}`} {...rest}>
      {(title || action) && (
        <div className="flex items-end justify-between gap-3">
          <div>
            {title && <h2 className="text-sm font-semibold text-foreground">{title}</h2>}
            {description && <p className="text-xs text-muted-foreground mt-0.5">{description}</p>}
          </div>
          {action && <div className="flex-shrink-0">{action}</div>}
        </div>
      )}
      {children}
    </section>
  )
}

// ─── EmptyState ─────────────────────────────────────────────────────────────

type EmptyStateProps = {
  icon?: React.ReactNode
  title: string
  description?: string
  action?: React.ReactNode
  className?: string
}

export function EmptyState({ icon, title, description, action, className = "" }: EmptyStateProps) {
  return (
    <div className={`flex flex-col items-center justify-center text-center py-10 px-6 ${className}`}>
      {icon && <div className="text-muted-foreground/40 mb-3">{icon}</div>}
      <p className="text-sm font-medium text-foreground">{title}</p>
      {description && <p className="text-xs text-muted-foreground mt-1.5 max-w-sm">{description}</p>}
      {action && <div className="mt-5">{action}</div>}
    </div>
  )
}

// ─── StatTile ────────────────────────────────────────────────────────────────
//
// Big number with a small label. Used in dashboard headers + Console.

type StatTileProps = {
  label: string
  value: string | number
  trend?: { delta: number; suffix?: string }
  hint?: string
  className?: string
}

export function StatTile({ label, value, trend, hint, className = "" }: StatTileProps) {
  return (
    <div className={`flex flex-col gap-1 rounded-xl border border-border bg-card p-4 ${className}`}>
      <p className="text-xs text-muted-foreground">{label}</p>
      <div className="flex items-baseline gap-2">
        <p className="text-2xl font-semibold tabular-nums tracking-tight text-foreground">{value}</p>
        {trend && (
          <span className={`text-xs ${trend.delta >= 0 ? "text-nexus-success" : "text-destructive"}`}>
            {trend.delta >= 0 ? "+" : ""}{trend.delta}{trend.suffix ?? ""}
          </span>
        )}
      </div>
      {hint && <p className="text-xs text-muted-foreground/70">{hint}</p>}
    </div>
  )
}

// ─── Skeleton ───────────────────────────────────────────────────────────────

export function Skeleton({ className = "" }: { className?: string }) {
  return <div className={`animate-pulse rounded-md bg-muted ${className}`} />
}

// ─── Tabs ────────────────────────────────────────────────────────────────────
//
// Pill-style tabs. Active tab has a soft surface; rest are quiet.

type Tab = { id: string; label: string; icon?: React.ReactNode }

type TabsProps = {
  tabs: Tab[]
  active: string
  onChange: (id: string) => void
  className?: string
}

export function Tabs({ tabs, active, onChange, className = "" }: TabsProps) {
  return (
    <div className={`inline-flex p-1 gap-1 rounded-lg bg-muted ${className}`}>
      {tabs.map(t => {
        const isActive = t.id === active
        return (
          <button
            key={t.id}
            onClick={() => onChange(t.id)}
            className={`flex items-center gap-1.5 h-8 px-3 rounded-md text-sm font-medium transition-colors whitespace-nowrap ${
              isActive
                ? "bg-card text-foreground shadow-sm"
                : "text-muted-foreground hover:text-foreground"
            }`}
          >
            {t.icon}
            {t.label}
          </button>
        )
      })}
    </div>
  )
}
