"use client"

import Link from "next/link"
import { usePathname, useRouter } from "next/navigation"
import { useState, useEffect } from "react"
import {
  LayoutDashboard, MessageSquare, Workflow, Bot,
  Map, Users, Brain, LogOut, Palette, X,
  ChevronRight, Activity, Shield, Globe, Settings, Terminal, Zap, CalendarClock, Cpu,
} from "lucide-react"
import ThemePicker from "@/components/dashboard/ThemePicker"
import { useTheme } from "@/hooks/useTheme"
import { UserAvatar } from "@/components/ui/UserAvatar"

const NAV = [
  { label: "Overview",   href: "/dashboard",            icon: LayoutDashboard, shortLabel: "Home" },
  { label: "Eve",        href: "/dashboard/maxwell",    icon: MessageSquare,   shortLabel: "Eve" },
  { label: "Operations", href: "/dashboard/operations", icon: Workflow,        shortLabel: "Ops" },
  { label: "Agents",     href: "/dashboard/agents",     icon: Bot,             shortLabel: "Agents" },
  { label: "Arena",      href: "/dashboard/arena",      icon: Zap,             shortLabel: "Arena" },
  { label: "Nexus Map",  href: "/dashboard/map",        icon: Map,             shortLabel: "Map" },
  { label: "Humans",     href: "/dashboard/humans",     icon: Users,           shortLabel: "Humans" },
  { label: "Groups",     href: "/dashboard/groups",     icon: Globe,           shortLabel: "Groups" },
  { label: "Directives", href: "/dashboard/directives", icon: Brain,           shortLabel: "Rules" },
  { label: "Calendar",   href: "/dashboard/calendar",   icon: CalendarClock,   shortLabel: "Cal" },
  { label: "Partybot",   href: "/dashboard/partybot",   icon: Cpu,             shortLabel: "Bot" },
  { label: "Console",    href: "/dashboard/console",    icon: Terminal,        shortLabel: "Console" },
]

// On mobile, we surface every desktop nav item via a horizontally
// scrollable bottom strip rather than truncating to the first five.
// Cutting Map / Humans / Groups / Directives / Calendar / Console off
// from mobile cuts users off from data they expect to reach.
const MOBILE_NAV = NAV

export default function DashboardSidebar({ userEmail, userName, userRole, userAvatarUrl }: { userEmail: string; userName?: string; userRole?: string; userAvatarUrl?: string | null }) {
  const pathname = usePathname()
  const router = useRouter()
  const { resolved } = useTheme()
  const [loggingOut, setLoggingOut] = useState(false)
  const [showTheme, setShowTheme] = useState(false)
  const [time, setTime] = useState("")
  const [systemStatus] = useState("OPERATIONAL")

  useEffect(() => {
    const update = () => setTime(new Date().toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: false }))
    update()
    const id = setInterval(update, 1000)
    return () => clearInterval(id)
  }, [])

  async function handleSignOut() {
    if (loggingOut) return
    setLoggingOut(true)
    try { await fetch("/api/security/logout", { method: "POST" }) }
    finally { router.push("/") }
  }

  function isActive(href: string) {
    return pathname === href || (href !== "/dashboard" && pathname.startsWith(href))
  }

  // Simple theme = Apple-style clean design
  if (resolved.isSimple) {
    return (
      <>
        {/* ── SIMPLE DESKTOP SIDEBAR ─────────────────────────────────────── */}
        <aside className="hidden lg:flex fixed left-0 top-0 bottom-0 w-72 flex-col z-40 bg-sidebar border-r border-sidebar-border">
          {/* Header */}
          <div className="px-6 py-6 flex-shrink-0">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center">
                <span className="text-sm font-bold text-primary">NX</span>
              </div>
              <div>
                <p className="text-base font-semibold text-sidebar-foreground">Nexus</p>
                <p className="text-xs text-muted-foreground">Command Platform</p>
              </div>
            </div>

            {/* Status pill */}
            <div className="mt-4 px-3 py-2 rounded-xl bg-secondary flex items-center justify-between">
              <div className="flex items-center gap-2">
                <div className="w-2 h-2 rounded-full bg-nexus-success" />
                <span className="text-xs font-medium text-secondary-foreground">{systemStatus}</span>
              </div>
              <span className="text-xs font-mono text-muted-foreground">{time}</span>
            </div>
          </div>

          {/* Navigation */}
          <nav className="flex-1 px-3 py-2 flex flex-col gap-1 overflow-y-auto">
            <p className="px-3 mb-2 text-[10px] font-semibold uppercase tracking-wider text-muted-foreground">Systems</p>

            {NAV.map(({ label, href, icon: Icon }) => {
              const active = isActive(href)
              return (
                <Link key={href} href={href}
                  className={`flex items-center gap-3 px-3 py-2.5 rounded-xl transition-all duration-200 ${
                    active
                      ? "bg-primary/10 text-primary"
                      : "text-muted-foreground hover:bg-secondary hover:text-sidebar-foreground"
                  }`}
                >
                  <Icon size={18} className={active ? "text-primary" : ""} />
                  <span className="text-sm font-medium">{label}</span>
                  {active && <ChevronRight size={14} className="ml-auto text-primary/60" />}
                </Link>
              )
            })}
          </nav>

          {/* Footer */}
          <div className="px-3 pb-4 pt-3 border-t border-sidebar-border">
            {/* User card — clickable to /dashboard/settings */}
            <Link href="/dashboard/settings"
              className="px-4 py-3 rounded-xl bg-secondary mb-3 flex items-center gap-3 hover:bg-muted transition-colors"
            >
              <UserAvatar name={userName || userEmail} src={userAvatarUrl} size="md" ring="none" />

              <div className="min-w-0 flex-1">
                <p className="text-sm font-medium text-sidebar-foreground truncate">{userName || userEmail}</p>
                <p className="text-xs text-muted-foreground">{userRole === 'director' ? 'Director Access' : userRole === 'admin' ? 'Admin Access' : 'Member Access'}</p>
              </div>
              <Settings size={14} className="text-muted-foreground/50 flex-shrink-0" />
            </Link>

            {/* Sign out — Theme toggle hidden until light mode is supported cleanly across all components. */}
            <button onClick={handleSignOut} disabled={loggingOut}
              className="w-full flex items-center justify-center gap-2 py-2.5 rounded-xl text-xs font-medium bg-secondary text-muted-foreground hover:bg-destructive/10 hover:text-destructive transition-all duration-200 disabled:opacity-40"
            >
              <LogOut size={14} />
              {loggingOut ? "..." : "Sign out"}
            </button>
          </div>
        </aside>

        {/* ── SIMPLE MOBILE BOTTOM TAB BAR ───────────────────────────────── */}
        <nav className="lg:hidden fixed bottom-0 left-0 right-0 z-50 bg-sidebar/95 backdrop-blur-xl border-t border-sidebar-border"
          style={{ paddingBottom: "max(12px, env(safe-area-inset-bottom))" }}
        >
          <div className="overflow-x-auto scrollbar-thin">
            <div className="flex items-center gap-1 px-2 pt-2 w-max">
              {MOBILE_NAV.map(({ href, icon: Icon, shortLabel }) => {
                const active = isActive(href)
                return (
                  <Link key={href} href={href}
                    className={`flex flex-col items-center gap-1 px-4 py-2 rounded-xl transition-all duration-200 min-w-[64px] ${
                      active ? "text-primary bg-primary/8" : "text-muted-foreground"
                    }`}
                  >
                    <Icon size={22} />
                    <span className="text-[10px] font-medium">{shortLabel}</span>
                  </Link>
                )
              })}
            </div>
          </div>
        </nav>
      </>
    )
  }

  // Futuristic theme = Iron Man / Tron HUD
  return (
    <>
      {/* ── FUTURISTIC DESKTOP SIDEBAR — IRON MAN HUD ────────────────────── */}
      <aside className="hidden lg:flex fixed left-0 top-0 bottom-0 w-72 flex-col z-40 overflow-hidden bg-sidebar border-r border-sidebar-border">
        {/* Animated scan line */}
        <div className="absolute inset-0 pointer-events-none overflow-hidden opacity-30">
          <div className="absolute left-0 right-0 h-[2px] nexus-scanline" />
        </div>

        {/* Grid overlay */}
        <div className="absolute inset-0 pointer-events-none nexus-grid-bg opacity-50" />

        {/* Header with hexagonal logo */}
        <div className="relative px-5 py-5 flex-shrink-0">
          <div className="flex items-center gap-4">
            {/* Hexagonal arc reactor logo */}
            <div className="relative">
              <div className="w-12 h-12 flex items-center justify-center bg-primary/15"
                style={{ clipPath: "polygon(50% 0%, 100% 25%, 100% 75%, 50% 100%, 0% 75%, 0% 25%)" }}
              >
                <div className="w-10 h-10 flex items-center justify-center bg-primary/20 nexus-glow-cyan"
                  style={{ clipPath: "polygon(50% 0%, 100% 25%, 100% 75%, 50% 100%, 0% 75%, 0% 25%)" }}
                >
                  <span className="text-xs font-black tracking-tight text-primary nexus-glow-text">NX</span>
                </div>
              </div>
              {/* Status indicator */}
              <div className="absolute -bottom-0.5 -right-0.5 w-3 h-3 rounded-full bg-background flex items-center justify-center border border-nexus-success/50">
                <div className="w-1.5 h-1.5 rounded-full bg-nexus-success animate-pulse" />
              </div>
            </div>
            <div>
              <p className="text-base font-bold tracking-wide text-sidebar-foreground">NEXUS</p>
              <p className="text-[10px] font-semibold tracking-[0.2em] uppercase text-primary/60">Command Platform</p>
            </div>
          </div>

          {/* System status bar */}
          <div className="mt-4 px-3 py-2 rounded-lg bg-primary/5 border border-primary/10 flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Shield size={12} className="text-nexus-success" />
              <span className="text-[10px] font-bold tracking-wider text-nexus-success">{systemStatus}</span>
            </div>
            <div className="flex items-center gap-2">
              <Activity size={10} className="text-primary/50" />
              <span className="text-[10px] font-mono text-primary/70">{time}</span>
            </div>
          </div>
        </div>

        {/* Navigation */}
        <nav className="flex-1 px-3 py-4 flex flex-col gap-0.5 overflow-y-auto">
          <p className="px-3 mb-3 text-[9px] font-bold tracking-[0.25em] uppercase text-primary/35">Systems</p>

          {NAV.map(({ label, href, icon: Icon }) => {
            const active = isActive(href)
            return (
              <Link key={href} href={href}
                className={`group relative flex items-center gap-3 px-4 py-3 rounded-lg transition-all duration-300 ${
                  active
                    ? "bg-gradient-to-r from-primary/12 to-primary/3 border-l-2 border-primary"
                    : "border-l-2 border-transparent hover:bg-primary/5"
                }`}
              >
                <div className="relative">
                  <Icon size={18}
                    className={`transition-all duration-300 ${
                      active ? "text-primary drop-shadow-[0_0_8px_var(--nexus-cyan)]" : "text-muted-foreground group-hover:text-sidebar-foreground"
                    }`}
                  />
                  {active && (
                    <div className="absolute -inset-1 rounded-full bg-primary/20 blur-sm" />
                  )}
                </div>

                <span className={`text-[13px] font-medium tracking-wide transition-colors duration-300 ${
                  active ? "text-sidebar-foreground" : "text-muted-foreground group-hover:text-sidebar-foreground"
                }`}>
                  {label}
                </span>

                {active && <ChevronRight size={14} className="ml-auto text-primary/60" />}
              </Link>
            )
          })}
        </nav>

        {/* Footer */}
        <div className="px-3 pb-4 pt-3 border-t border-sidebar-border">
          {/* User card — clickable to /dashboard/settings */}
          <Link href="/dashboard/settings"
            className="px-4 py-3 rounded-xl mb-3 flex items-center gap-3 bg-gradient-to-r from-primary/5 to-purple-500/5 border border-primary/10 hover:border-primary/30 hover:from-primary/10 hover:to-purple-500/10 transition-all"
          >
            <UserAvatar name={userName || userEmail} src={userAvatarUrl} size="md" ring="none" />

            <div className="min-w-0 flex-1">
              <p className="text-xs font-semibold text-sidebar-foreground truncate">{userName || userEmail}</p>
              <p className="text-[10px] font-medium text-primary/60">{userRole === 'director' ? 'Director Access' : userRole === 'admin' ? 'Admin Access' : 'Member Access'}</p>
            </div>
            <Settings size={14} className="text-primary/40 flex-shrink-0" />
          </Link>

          {/* Sign out — Theme toggle hidden until light mode is supported cleanly across all components. */}
          <button onClick={handleSignOut} disabled={loggingOut}
            className="w-full flex items-center justify-center gap-2 py-2.5 rounded-lg text-xs font-semibold transition-all duration-300 border bg-secondary border-border text-muted-foreground hover:bg-destructive/10 hover:border-destructive/30 hover:text-destructive disabled:opacity-40"
          >
            <LogOut size={14} />
            {loggingOut ? "..." : "Sign out"}
          </button>
        </div>
      </aside>

      {/* ── FUTURISTIC MOBILE BOTTOM TAB BAR — TRON STYLE ────────────────── */}
      <nav className="lg:hidden fixed bottom-0 left-0 right-0 z-50 bg-sidebar/95 backdrop-blur-xl border-t border-primary/15"
        style={{ paddingBottom: "max(12px, env(safe-area-inset-bottom))" }}
      >
        {/* Top glow line */}
        <div className="absolute top-0 left-0 right-0 h-[1px] bg-gradient-to-r from-transparent via-primary/50 to-transparent" />

        <div className="overflow-x-auto scrollbar-thin">
          <div className="flex items-center gap-1 px-2 pt-2 w-max">
            {MOBILE_NAV.map(({ href, icon: Icon, shortLabel }) => {
              const active = isActive(href)
              return (
                <Link key={href} href={href}
                  className={`flex flex-col items-center gap-1.5 px-4 py-2 rounded-xl transition-all duration-300 min-w-[64px] ${
                    active ? "bg-primary/10" : ""
                  }`}
                >
                  <div className="relative">
                    <Icon size={24}
                      className={`transition-all duration-300 ${
                        active ? "text-primary drop-shadow-[0_0_10px_var(--nexus-cyan)]" : "text-muted-foreground"
                      }`}
                    />
                    {active && (
                      <span className="absolute -top-0.5 -right-0.5 w-2 h-2 rounded-full bg-primary animate-pulse" />
                    )}
                  </div>
                  <span className={`text-[10px] font-semibold tracking-wide ${
                    active ? "text-primary" : "text-muted-foreground"
                  }`}>
                    {shortLabel}
                  </span>
                </Link>
              )
            })}
          </div>
        </div>
      </nav>
    </>
  )
}
