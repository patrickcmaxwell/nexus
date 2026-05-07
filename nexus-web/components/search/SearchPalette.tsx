"use client"

import { useEffect, useRef, useState } from "react"
import { useRouter } from "next/navigation"
import {
  MessageSquare, Workflow, FileText, Bot, Sparkles, ScrollText,
  Search, X, CornerDownLeft,
} from "lucide-react"
import { useGlobalKeybinding } from "@/hooks/useGlobalKeybinding"

// SearchPalette
//
// Cmd-K overlay for unified search across the active human's cached data.
// Hits /api/search and renders results grouped by kind. Mirrors Lumen's
// SearchPalette.swift behavior: instant fuzzy results, keyboard nav, kind
// badges, route-on-enter.
//
// Mounted at the dashboard layout level so it's available on every page.
// The Cmd-K binding lives here so any new dashboard page picks it up
// automatically.

export type SearchHit = {
  kind: "conversation" | "operation" | "record" | "agent" | "memory" | "directive"
  id: string
  label: string
  snippet: string
}

const KIND_META: Record<SearchHit["kind"], { icon: typeof MessageSquare; color: string; bg: string; href: (id: string) => string }> = {
  conversation: { icon: MessageSquare, color: "var(--nexus-cyan)",            bg: "oklch(0.75 0.18 200 / 0.12)", href: (id) => `/dashboard/maxwell?c=${id}` },
  operation:    { icon: Workflow,      color: "oklch(0.78 0.18 50)",          bg: "oklch(0.78 0.18 50 / 0.12)",  href: (id) => `/dashboard/operations?op=${id}` },
  record:       { icon: FileText,      color: "oklch(0.85 0.16 90)",          bg: "oklch(0.85 0.16 90 / 0.12)",  href: (id) => `/dashboard/operations?record=${id}` },
  agent:        { icon: Bot,           color: "oklch(0.65 0.22 290)",         bg: "oklch(0.65 0.22 290 / 0.12)", href: (id) => `/dashboard/agents?id=${id}` },
  memory:       { icon: Sparkles,      color: "oklch(0.78 0.18 155)",         bg: "oklch(0.78 0.18 155 / 0.12)", href: (_)  => `/dashboard/maxwell` },  // memory bank surfaces in Eve
  directive:    { icon: ScrollText,    color: "oklch(0.78 0.18 350)",         bg: "oklch(0.78 0.18 350 / 0.12)", href: (_)  => `/dashboard/directives` },
}

export default function SearchPalette() {
  const router = useRouter()
  const [open, setOpen] = useState(false)
  const [query, setQuery] = useState("")
  const [hits, setHits] = useState<SearchHit[]>([])
  const [selection, setSelection] = useState(0)
  const [loading, setLoading] = useState(false)
  const inputRef = useRef<HTMLInputElement>(null)
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  // Global Cmd-K binding
  useGlobalKeybinding("k", { meta: true }, () => {
    setOpen(true)
  }, [])

  // Focus input when opened
  useEffect(() => {
    if (open) {
      const t = setTimeout(() => inputRef.current?.focus(), 50)
      return () => clearTimeout(t)
    }
  }, [open])

  // Debounced search — 80ms feels instant but groups multi-key bursts.
  useEffect(() => {
    if (debounceRef.current) clearTimeout(debounceRef.current)
    if (!open) return
    const trimmed = query.trim()
    if (!trimmed) { setHits([]); setSelection(0); return }
    debounceRef.current = setTimeout(async () => {
      setLoading(true)
      try {
        const res = await fetch(`/api/search?q=${encodeURIComponent(trimmed)}`, { credentials: "include" })
        if (res.ok) {
          const data = await res.json()
          setHits(data.hits ?? [])
          setSelection(0)
        }
      } finally {
        setLoading(false)
      }
    }, 80)
  }, [query, open])

  // Keyboard nav inside the palette
  useEffect(() => {
    if (!open) return
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") {
        e.preventDefault()
        close()
      } else if (e.key === "ArrowDown") {
        e.preventDefault()
        setSelection((s) => Math.min(hits.length - 1, s + 1))
      } else if (e.key === "ArrowUp") {
        e.preventDefault()
        setSelection((s) => Math.max(0, s - 1))
      } else if (e.key === "Enter") {
        e.preventDefault()
        const hit = hits[selection]
        if (hit) {
          router.push(KIND_META[hit.kind].href(hit.id))
          close()
        }
      }
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [open, hits, selection, router])

  function close() {
    setOpen(false)
    setQuery("")
    setHits([])
    setSelection(0)
  }

  if (!open) return null

  return (
    <div
      className="fixed inset-0 z-[100] flex items-start justify-center pt-24 px-4 bg-black/55 backdrop-blur-sm"
      onClick={close}
    >
      <div
        className="w-full max-w-xl overflow-hidden"
        onClick={(e) => e.stopPropagation()}
        style={{
          background: "oklch(0.10 0.015 240 / 0.98)",
          border: "1px solid oklch(0.75 0.18 200 / 0.3)",
          borderRadius: 12,
          boxShadow: "0 20px 60px oklch(0.75 0.18 200 / 0.18)",
        }}
      >
        {/* Input row */}
        <div className="flex items-center gap-3 px-4 py-3 border-b border-white/5">
          <Search size={16} className="text-white/45" />
          <input
            ref={inputRef}
            type="text"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search operations, records, agents, memories…"
            className="flex-1 bg-transparent text-white text-base outline-none placeholder:text-white/35"
            autoComplete="off"
            spellCheck={false}
          />
          {query && (
            <button onClick={() => setQuery("")} className="text-white/35 hover:text-white/60">
              <X size={14} />
            </button>
          )}
          <span className="font-mono text-[9px] tracking-widest text-white/35 px-1.5 py-1 border border-white/10 rounded">
            ESC
          </span>
        </div>

        {/* Results */}
        <div className="max-h-[420px] overflow-auto">
          {!query && (
            <div className="px-5 py-6 text-sm text-white/45 space-y-3">
              <p>Type to search across all your data — instant.</p>
              <div className="flex flex-col gap-2 text-xs">
                <Hint shortcut="↑↓"  label="Navigate" />
                <Hint shortcut="↵"   label="Open the highlighted result" />
                <Hint shortcut="ESC" label="Dismiss" />
              </div>
            </div>
          )}

          {query && !loading && hits.length === 0 && (
            <div className="px-5 py-6 text-sm text-white/45">
              No matches. Try a different word or fewer characters.
            </div>
          )}

          {hits.length > 0 && (
            <ul>
              {hits.map((hit, idx) => {
                const meta = KIND_META[hit.kind]
                const Icon = meta.icon
                const selected = idx === selection
                return (
                  <li
                    key={`${hit.kind}-${hit.id}`}
                    className="cursor-pointer"
                    onMouseEnter={() => setSelection(idx)}
                    onClick={() => {
                      router.push(meta.href(hit.id))
                      close()
                    }}
                    style={{
                      background: selected ? "oklch(0.75 0.18 200 / 0.08)" : "transparent",
                      borderLeft: `2px solid ${selected ? meta.color : "transparent"}`,
                    }}
                  >
                    <div className="flex items-center gap-3 px-4 py-3">
                      <span
                        className="flex items-center justify-center"
                        style={{ background: meta.bg, color: meta.color, width: 24, height: 24, borderRadius: 6, border: `1px solid ${meta.color}55` }}
                      >
                        <Icon size={12} />
                      </span>
                      <div className="flex-1 min-w-0">
                        <p className="text-sm text-white/90 truncate">{hit.label}</p>
                        {hit.snippet && (
                          <p className="text-xs text-white/45 truncate">{hit.snippet}</p>
                        )}
                      </div>
                      {selected && (
                        <CornerDownLeft size={12} className="text-white/45" />
                      )}
                    </div>
                  </li>
                )
              })}
            </ul>
          )}
        </div>

        {/* Footer */}
        <div className="px-4 py-2 flex items-center justify-between border-t border-white/5 bg-white/[0.015]">
          <span className="font-mono text-[9px] tracking-widest text-white/35">
            {hits.length > 0 ? `${hits.length} RESULT${hits.length === 1 ? "" : "S"}` : ""}
          </span>
          <span className="font-mono text-[9px] tracking-widest" style={{ color: "var(--nexus-cyan)" }}>
            NEXUS SEARCH
          </span>
        </div>
      </div>
    </div>
  )
}

function Hint({ shortcut, label }: { shortcut: string; label: string }) {
  return (
    <div className="flex items-center gap-3">
      <span className="font-mono text-[10px] tracking-widest text-white/55 px-1.5 py-0.5 border border-white/15 rounded min-w-[32px] text-center">
        {shortcut}
      </span>
      <span className="text-white/55">{label}</span>
    </div>
  )
}
