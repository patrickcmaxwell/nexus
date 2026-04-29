"use client"

import { useCallback, useEffect, useImperativeHandle, useRef, useState, forwardRef } from "react"
import MentionPicker, { type MentionPickerHandle } from "./MentionPicker"
import { MENTION_TYPE_COLORS } from "@/lib/mentions/types"
import type { MentionResult, MentionType } from "@/lib/mentions/types"

// A reusable contentEditable-based input that supports inline @mention chips.
//
// Design constraints driving this implementation:
//  - Chips are real DOM elements (<span contenteditable="false">) so browser
//    selection/deletion treats them atomically (backspace kills the whole
//    chip).
//  - We serialize to/from our token syntax `@[label](type:id)` so the value
//    is plain text on the wire and in the DB.
//  - The parent controls value through `value`/`onChange`, just like a
//    normal input — reconciliation is one-way: when `value` changes from
//    outside AND differs from the current serialization, we rebuild the DOM.
//    This avoids caret jumping while the user is typing.
//  - Submit on Enter, Shift+Enter for newline, Esc cancels the picker.

export type MentionInputHandle = {
  focus: () => void
  clear: () => void
  insertText: (text: string) => void
}

type Props = {
  value: string
  onChange: (value: string) => void
  onSubmit?: () => void
  placeholder?: string
  disabled?: boolean
  className?: string
  minHeightClass?: string  // e.g. "min-h-[42px]"
  maxHeightClass?: string  // e.g. "max-h-[120px]"
  // When true: no built-in padding, border, background, or rounding — use
  // when the parent provides its own styled container (e.g. the Maxwell
  // chat input which has its own bordered frame around the editor + buttons).
  unstyled?: boolean
  // Optional scroll container ref; picker clips itself within this bounds.
  boundsRef?: React.RefObject<HTMLElement | null>
  // Optional right-side adornment rendered inside the editor's right padding
  // area (e.g. a Send button). Positioned absolute by the caller.
  rightAdornment?: React.ReactNode
}

// Convert the editor's DOM back to our token syntax.
function serializeDom(root: HTMLElement): string {
  let out = ""
  const walk = (node: Node) => {
    if (node.nodeType === Node.TEXT_NODE) {
      out += (node.textContent ?? "")
      return
    }
    if (node.nodeType !== Node.ELEMENT_NODE) return
    const el = node as HTMLElement
    // Mention chip
    if (el.dataset.mentionChip) {
      const [type, id] = el.dataset.mentionChip.split(":")
      const label = el.dataset.mentionLabel ?? el.textContent ?? ""
      out += `@[${label}](${type}:${id})`
      return
    }
    if (el.tagName === "BR") { out += "\n"; return }
    // For <div> (new paragraph) or <p>, prepend a newline unless we're at the start
    if (el.tagName === "DIV" || el.tagName === "P") {
      if (out.length && !out.endsWith("\n")) out += "\n"
    }
    for (const child of Array.from(el.childNodes)) walk(child)
  }
  for (const child of Array.from(root.childNodes)) walk(child)
  return out
}

// Build DOM from our token syntax. Returns an array of nodes to inject.
function tokensToDom(value: string, doc: Document): Node[] {
  const TOKEN_RE = /@\[([^\]\n]+)\]\((operation|record|conversation|topic|agent):([a-zA-Z0-9_-]+)\)/g
  const out: Node[] = []
  let last = 0
  let m: RegExpExecArray | null
  const pushText = (text: string) => {
    // Split on \n to create explicit <br>s so multi-line pastes render.
    const parts = text.split("\n")
    parts.forEach((part, i) => {
      if (part) out.push(doc.createTextNode(part))
      if (i < parts.length - 1) out.push(doc.createElement("br"))
    })
  }
  TOKEN_RE.lastIndex = 0
  while ((m = TOKEN_RE.exec(value)) !== null) {
    if (m.index > last) pushText(value.slice(last, m.index))
    out.push(buildChipNode(doc, { type: m[2] as MentionType, id: m[3], label: m[1] }))
    last = m.index + m[0].length
  }
  if (last < value.length) pushText(value.slice(last))
  return out
}

function buildChipNode(doc: Document, token: { type: MentionType; id: string; label: string }): HTMLElement {
  const colors = MENTION_TYPE_COLORS[token.type]
  const span = doc.createElement("span")
  span.setAttribute("contenteditable", "false")
  span.dataset.mentionChip = `${token.type}:${token.id}`
  span.dataset.mentionLabel = token.label
  // Match MentionChip styling — tiny inline pill.
  span.className = "inline-flex items-center gap-1 px-1.5 py-0.5 rounded font-medium align-baseline border leading-[1.3] text-[11.5px]"
  span.style.color = colors.fg
  span.style.background = colors.bg
  span.style.borderColor = colors.border
  span.style.userSelect = "none"
  // Simple "@label" rendering — we don't try to render the type icon inside
  // the editor because DOM-level icons are fiddly to keep in sync. The icon
  // appears in the picker and in rendered messages, which is enough.
  span.textContent = `@${token.label}`
  return span
}

// Get the caret position as a (top, left) pair relative to viewport for anchoring the popover.
function caretViewportRect(): { top: number; left: number; bottom: number } | null {
  const sel = window.getSelection()
  if (!sel || sel.rangeCount === 0) return null
  const range = sel.getRangeAt(0).cloneRange()
  // Shrink range to caret (end-point)
  range.collapse(true)
  const rects = range.getClientRects()
  let r = rects[0]
  if (!r) {
    // Edge case: caret at the very start of an empty element. Use the
    // element's bounding box.
    const anchor = range.startContainer
    const el = anchor.nodeType === Node.ELEMENT_NODE ? anchor as Element : (anchor.parentElement as Element)
    if (!el) return null
    r = el.getBoundingClientRect()
  }
  return { top: r.bottom + 6, left: r.left, bottom: r.top }
}

// Find the `@query` fragment that the caret is currently editing. Returns the
// query text plus a Range that spans `@query` so we can replace it on pick.
function findActiveMentionQuery(): { query: string; range: Range } | null {
  const sel = window.getSelection()
  if (!sel || sel.rangeCount === 0 || !sel.isCollapsed) return null
  const range = sel.getRangeAt(0)
  const node = range.startContainer
  if (node.nodeType !== Node.TEXT_NODE) return null
  const text = node.textContent ?? ""
  const offset = range.startOffset
  // Scan back for @ — stop if we hit whitespace or the start
  let i = offset - 1
  while (i >= 0) {
    const c = text[i]
    if (c === "@") break
    if (/\s/.test(c)) return null
    i--
  }
  if (i < 0) return null
  // Must be at start of string, or preceded by whitespace (no bare emails)
  if (i > 0 && !/\s/.test(text[i - 1])) return null
  const query = text.slice(i + 1, offset)
  // Build a range covering `@query`
  const replace = document.createRange()
  replace.setStart(node, i)
  replace.setEnd(node, offset)
  return { query, range: replace }
}

const MentionInput = forwardRef<MentionInputHandle, Props>(function MentionInput(
  { value, onChange, onSubmit, placeholder, disabled, className, minHeightClass = "min-h-[42px]", maxHeightClass = "max-h-[200px]", unstyled, boundsRef, rightAdornment },
  ref,
) {
  const editorRef = useRef<HTMLDivElement>(null)
  const pickerRef = useRef<MentionPickerHandle>(null)
  const lastSerializedRef = useRef<string>("")  // Tracks last value serialized FROM our own DOM, for reconciliation
  const [picker, setPicker] = useState<{ query: string; anchor: { top: number; left: number } | null; range: Range } | null>(null)
  const [isFocused, setIsFocused] = useState(false)

  // Initialize / reconcile the editor DOM when `value` changes externally.
  useEffect(() => {
    const el = editorRef.current
    if (!el) return
    if (value === lastSerializedRef.current) return  // Value came FROM us — no-op.
    // Rebuild from scratch.
    el.innerHTML = ""
    const nodes = tokensToDom(value, el.ownerDocument)
    for (const n of nodes) el.appendChild(n)
    lastSerializedRef.current = value
  }, [value])

  useImperativeHandle(ref, () => ({
    focus() { editorRef.current?.focus() },
    clear() {
      if (!editorRef.current) return
      editorRef.current.innerHTML = ""
      lastSerializedRef.current = ""
      onChange("")
    },
    insertText(text: string) {
      const el = editorRef.current
      if (!el) return
      el.focus()
      document.execCommand("insertText", false, text)
    },
  }), [onChange])

  // Serialize on every input and notify parent. Also detect @-query.
  const handleInput = useCallback(() => {
    const el = editorRef.current
    if (!el) return
    const serialized = serializeDom(el)
    lastSerializedRef.current = serialized
    onChange(serialized)

    const active = findActiveMentionQuery()
    if (active) {
      const caret = caretViewportRect()
      setPicker({ query: active.query, anchor: caret ? { top: caret.top, left: caret.left } : null, range: active.range })
    } else {
      setPicker(null)
    }
  }, [onChange])

  // When a picker result is selected, replace `@query` with a chip node.
  const pickResult = useCallback((r: MentionResult) => {
    if (!picker) return
    const el = editorRef.current
    if (!el) return
    el.focus()
    try {
      // Delete the `@query` text
      picker.range.deleteContents()
      // Insert chip + a trailing space
      const chip = buildChipNode(el.ownerDocument, { type: r.type, id: r.id, label: r.label })
      picker.range.insertNode(chip)
      const space = el.ownerDocument.createTextNode("\u00A0")  // non-breaking so it doesn't collapse
      chip.after(space)
      // Move caret after the space
      const sel = window.getSelection()
      if (sel) {
        const newRange = el.ownerDocument.createRange()
        newRange.setStartAfter(space)
        newRange.collapse(true)
        sel.removeAllRanges()
        sel.addRange(newRange)
      }
    } catch (err) {
      // eslint-disable-next-line no-console
      console.error("[v0] mention insert failed:", err)
    }
    setPicker(null)
    // Trigger a change notification
    handleInput()
  }, [picker, handleInput])

  const handleKeyDown = useCallback((e: React.KeyboardEvent<HTMLDivElement>) => {
    // If picker is open, let it consume Arrow/Enter/Tab/Esc first.
    if (picker && pickerRef.current) {
      // We convert the React event to a plain KeyboardEvent shim for the picker.
      const shim = { key: e.key, preventDefault: () => e.preventDefault() } as unknown as KeyboardEvent
      const handled = pickerRef.current.handleKey(shim)
      if (handled) { e.preventDefault(); return }
    }
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault()
      onSubmit?.()
      return
    }
    if (e.key === "Enter" && e.shiftKey) {
      // Let browser insert line break naturally; Safari needs help though.
      // document.execCommand is deprecated but still the most reliable
      // cross-browser way to insert a <br> at caret inside a contenteditable.
      e.preventDefault()
      document.execCommand("insertLineBreak")
      return
    }
  }, [picker, onSubmit])

  // When the user clicks outside the editor, close the picker.
  useEffect(() => {
    if (!picker) return
    const onDown = (e: MouseEvent) => {
      const el = editorRef.current
      if (!el) return
      if (!el.contains(e.target as Node)) setPicker(null)
    }
    document.addEventListener("mousedown", onDown)
    return () => document.removeEventListener("mousedown", onDown)
  }, [picker])

  // Normalize paste to plain text so users can't accidentally inject markup
  // or weird styling from other apps.
  const handlePaste = useCallback((e: React.ClipboardEvent<HTMLDivElement>) => {
    e.preventDefault()
    const text = e.clipboardData.getData("text/plain")
    document.execCommand("insertText", false, text)
  }, [])

  return (
    <>
      <div className="relative flex-1">
        <div
          ref={editorRef}
          role="textbox"
          aria-multiline="true"
          contentEditable={!disabled}
          suppressContentEditableWarning
          onInput={handleInput}
          onKeyDown={handleKeyDown}
          onPaste={handlePaste}
          onFocus={() => setIsFocused(true)}
          onBlur={() => setIsFocused(false)}
          className={[
            "w-full outline-none whitespace-pre-wrap break-words overflow-y-auto",
            // Chrome/Safari gives an ugly default focus ring on contentEditable.
            // We control focus state via border below.
            unstyled
              ? "bg-transparent border-0 p-0 text-base leading-relaxed"
              : `px-3.5 py-2.5 pr-10 rounded-lg bg-secondary border text-[14px] leading-snug ${
                  isFocused ? "border-accent/50" : "border-border"
                }`,
            minHeightClass, maxHeightClass,
            disabled ? "opacity-50 pointer-events-none" : "",
            className ?? "",
          ].join(" ")}
          data-placeholder={placeholder ?? ""}
        />
        {/* Placeholder overlay — rendered only when editor is empty. */}
        {!value && placeholder && (
          <div
            className={[
              "absolute inset-0 pointer-events-none",
              unstyled
                ? "text-base leading-relaxed text-muted-foreground"
                : "px-3.5 py-2.5 text-[14px] leading-snug text-muted-foreground/60",
            ].join(" ")}
          >
            {placeholder}
          </div>
        )}
        {rightAdornment}
      </div>
      {picker && (
        <MentionPicker
          ref={pickerRef}
          query={picker.query}
          anchor={picker.anchor}
          onPick={pickResult}
          onCancel={() => setPicker(null)}
          boundsEl={boundsRef?.current ?? null}
        />
      )}
    </>
  )
})

export default MentionInput
