"use client"

import { useEffect, useState, useRef, useImperativeHandle, forwardRef } from "react"
import { createPortal } from "react-dom"
import { Briefcase, FileText, MessageSquare, Bot, Tag, Search } from "lucide-react"
import { MENTION_TYPE_COLORS, MENTION_TYPE_LABELS } from "@/lib/mentions/types"
import type { MentionResult, MentionType } from "@/lib/mentions/types"

// Popover shown while the user is typing `@query`. Groups results by type,
// supports arrow-key navigation, and exposes an imperative handle so the
// parent input can forward keyboard events that happen inside the input
// (Arrow/Enter/Escape) to us without stealing focus from the input.

type Props = {
  query: string
  // Pixel position where the popover should anchor — top-left corner.
  anchor: { top: number; left: number } | null
  onPick: (result: MentionResult) => void
  onCancel: () => void
  // Scroll container that the popover should reposition within; passed so we
  // can clip the anchor to visible bounds on small screens.
  boundsEl?: HTMLElement | null
}

export type MentionPickerHandle = {
  // Returns true if the event was handled by the picker (caller should
  // preventDefault). Lets the input route keys through.
  handleKey: (e: KeyboardEvent) => boolean
  // How many results are currently displayed (parent uses to decide whether
  // to swallow Enter when the popover is empty).
  size: () => number
}

const TYPE_ICONS: Record<MentionType, React.ComponentType<{ size?: number }>> = {
  operation: Briefcase, record: FileText, conversation: MessageSquare, topic: Tag, agent: Bot,
}

const MentionPicker = forwardRef<MentionPickerHandle, Props>(function MentionPicker(
  { query, anchor, onPick, onCancel, boundsEl },
  ref,
) {
  const [results, setResults] = useState<MentionResult[]>([])
  const [loading, setLoading] = useState(false)
  const [active, setActive] = useState(0)
  const abortRef = useRef<AbortController | null>(null)
  const containerRef = useRef<HTMLDivElement>(null)

  // Fetch results whenever the query changes. Debounce lightly so fast typing
  // doesn't flood the API.
  useEffect(() => {
    const ctrl = new AbortController()
    abortRef.current?.abort()
    abortRef.current = ctrl
    const timer = setTimeout(async () => {
      setLoading(true)
      try {
        const res = await fetch(`/api/mentions/search?q=${encodeURIComponent(query)}`, { signal: ctrl.signal })
        if (!res.ok) return
        const data = await res.json()
        setResults(data.results ?? [])
        setActive(0)
      } catch (err: unknown) {
        if ((err as { name?: string })?.name !== "AbortError") {
          // eslint-disable-next-line no-console
          console.error("[v0] mention search error:", err)
        }
      } finally {
        setLoading(false)
      }
    }, 120)
    return () => { clearTimeout(timer); ctrl.abort() }
  }, [query])

  // Keep the active row scrolled into view
  useEffect(() => {
    const el = containerRef.current?.querySelector(`[data-idx="${active}"]`)
    if (el) (el as HTMLElement).scrollIntoView({ block: "nearest" })
  }, [active])

  useImperativeHandle(ref, () => ({
    handleKey(e: KeyboardEvent) {
      if (results.length === 0 && e.key !== "Escape") return false
      if (e.key === "ArrowDown") { setActive(i => Math.min(i + 1, results.length - 1)); return true }
      if (e.key === "ArrowUp")   { setActive(i => Math.max(i - 1, 0));                    return true }
      if (e.key === "Enter" || e.key === "Tab") {
        const pick = results[active]
        if (pick) { onPick(pick); return true }
        return false
      }
      if (e.key === "Escape") { onCancel(); return true }
      return false
    },
    size: () => results.length,
  }), [results, active, onPick, onCancel])

  if (!anchor) return null
  if (typeof document === "undefined") return null

  // Always clip to the viewport (NOT to the input's scroll container, which
  // caused the previous clipping bug on the Maxwell chat input). We also
  // portal the popover to document.body so parent `transform` / `overflow`
  // rules never capture our `position: fixed` coordinates.
  const POP_WIDTH = 320
  const POP_HEIGHT = 320
  const vw = typeof window !== "undefined" ? window.innerWidth : 1920
  const vh = typeof window !== "undefined" ? window.innerHeight : 1080
  let top = anchor.top, left = anchor.left
  left = Math.max(8, Math.min(left, vw - POP_WIDTH - 8))
  // Flip above the caret if there's not enough room below.
  if (anchor.top + POP_HEIGHT > vh - 8) {
    top = Math.max(8, anchor.top - POP_HEIGHT - 24)
  }
  // boundsEl is intentionally ignored now — kept on the prop signature for
  // backward compatibility but viewport clipping covers all real cases.
  void boundsEl

  // Group results by type while preserving order (operations first, etc.)
  const grouped: Record<string, MentionResult[]> = {}
  for (const r of results) {
    if (!grouped[r.type]) grouped[r.type] = []
    grouped[r.type].push(r)
  }

  // Map flat index <-> group index for arrow navigation
  let flatIndex = -1

  const content = (
    <div
      ref={containerRef}
      className="fixed z-[100] w-[320px] max-h-[320px] overflow-y-auto rounded-lg border border-border bg-popover shadow-2xl text-popover-foreground"
      style={{ top, left }}
      onMouseDown={(e) => e.preventDefault() /* don't steal focus from input */}
    >
      <div className="flex items-center gap-2 px-3 py-2 border-b border-border/60 font-mono text-[10px] uppercase tracking-widest text-muted-foreground">
        <Search size={10} />
        <span>{query ? `"${query}"` : "Recent"}</span>
        {loading && <span className="ml-auto text-accent/70">loading…</span>}
      </div>
      {results.length === 0 && !loading && (
        <div className="px-3 py-6 text-center text-xs text-muted-foreground">
          No matches{query ? ` for "${query}"` : ""}.
        </div>
      )}
      {(Object.keys(grouped) as MentionType[]).map(type => {
        const rows = grouped[type]
        const Icon = TYPE_ICONS[type]
        const colors = MENTION_TYPE_COLORS[type]
        return (
          <div key={type}>
            <div className="flex items-center gap-1.5 px-3 pt-2 pb-1 font-mono text-[9px] uppercase tracking-widest" style={{ color: colors.fg }}>
              <Icon size={9} />
              {MENTION_TYPE_LABELS[type]}
            </div>
            {rows.map(r => {
              flatIndex++
              const idx = flatIndex
              const isActive = idx === active
              return (
                <button
                  key={`${r.type}:${r.id}`}
                  data-idx={idx}
                  onMouseEnter={() => setActive(idx)}
                  onClick={() => onPick(r)}
                  className="w-full text-left px-3 py-1.5 flex items-center gap-2 transition-colors"
                  style={{ background: isActive ? "rgba(255,255,255,0.05)" : "transparent" }}
                >
                  <span
                    className="w-1 self-stretch rounded"
                    style={{ background: isActive ? colors.fg : "transparent" }}
                  />
                  <div className="min-w-0 flex-1">
                    <div className="text-[13px] truncate text-foreground">{r.label}</div>
                    {r.sublabel && (
                      <div className="text-[11px] text-muted-foreground truncate">{r.sublabel}</div>
                    )}
                  </div>
                  {r.status && (
                    <span className="text-[9px] font-mono uppercase tracking-widest text-muted-foreground">{r.status}</span>
                  )}
                </button>
              )
            })}
          </div>
        )
      })}
    </div>
  )

  // Portal to document.body so ancestor transforms/overflow rules can never
  // clip the popover. This was the bug causing the picker to appear as a
  // stub showing only the header and group labels.
  return createPortal(content, document.body)
})

export default MentionPicker
