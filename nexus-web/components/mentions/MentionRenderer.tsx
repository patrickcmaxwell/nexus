"use client"

import { Fragment, type ReactNode, Children, isValidElement, cloneElement } from "react"
import MentionChip from "./MentionChip"
import { splitBySentinels } from "@/lib/mentions/parse"

// Given a string that may contain MENTION sentinels, return an array of
// React nodes where each sentinel is replaced with a live MentionChip.
export function renderSentinelString(text: string): ReactNode[] {
  const parts = splitBySentinels(text)
  return parts.map((p, i) => {
    if (p.kind === "text") return <Fragment key={i}>{p.text}</Fragment>
    return <MentionChip key={i} type={p.token.type} id={p.token.id} label={p.token.label} />
  })
}

// Recursively walk children and replace any string child with the
// sentinel-expanded version. Works for ReactMarkdown's component overrides
// because children come in as strings or React elements with string
// children.
export function expandMentionsInChildren(children: ReactNode): ReactNode {
  // Short-circuit when there are obviously no sentinels anywhere.
  // (We still need to recurse to find them in nested children.)
  return Children.map(children, (child) => {
    if (typeof child === "string") {
      if (!child.includes("\u200C[[MENTION:")) return child
      return <>{renderSentinelString(child)}</>
    }
    if (!isValidElement(child)) return child
    const props = child.props as { children?: ReactNode }
    const innerChildren = props.children
    if (innerChildren == null) return child
    return cloneElement(child, undefined, expandMentionsInChildren(innerChildren))
  })
}

// Render plain text (no markdown) with chips inline.
export function renderPlainWithMentions(text: string): ReactNode[] {
  // Plain text doesn't have sentinels — it has raw tokens. Reuse the
  // splitByMentions utility by protecting and splitting.
  if (!text) return []
  // Avoid a round-trip: split by the raw token regex directly.
  const TOKEN_RE = /@\[([^\]\n]+)\]\((operation|record|conversation|topic|agent):([a-zA-Z0-9_-]+)\)/g
  const parts: ReactNode[] = []
  let last = 0
  let m: RegExpExecArray | null
  let i = 0
  TOKEN_RE.lastIndex = 0
  while ((m = TOKEN_RE.exec(text)) !== null) {
    if (m.index > last) parts.push(<Fragment key={`t${i++}`}>{text.slice(last, m.index)}</Fragment>)
    parts.push(<MentionChip key={`c${i++}`} type={m[2] as "operation" | "record" | "conversation" | "topic" | "agent"} id={m[3]} label={m[1]} />)
    last = m.index + m[0].length
  }
  if (last < text.length) parts.push(<Fragment key={`t${i++}`}>{text.slice(last)}</Fragment>)
  return parts
}
