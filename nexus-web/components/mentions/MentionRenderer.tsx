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

// Render plain text (no markdown) with chips inline AND bare URLs autolinked.
// The two passes don't overlap (mention tokens use @[...] syntax, URLs start
// with http(s)://) so we can run them sequentially: split on mentions first,
// then linkify URLs inside each text fragment.
export function renderPlainWithMentions(text: string): ReactNode[] {
  if (!text) return []
  const TOKEN_RE = /@\[([^\]\n]+)\]\((operation|record|conversation|topic|agent):([a-zA-Z0-9_-]+)\)/g
  const parts: ReactNode[] = []
  let last = 0
  let m: RegExpExecArray | null
  let i = 0
  TOKEN_RE.lastIndex = 0
  while ((m = TOKEN_RE.exec(text)) !== null) {
    if (m.index > last) parts.push(...linkifyUrls(text.slice(last, m.index), `t${i++}`))
    parts.push(<MentionChip key={`c${i++}`} type={m[2] as "operation" | "record" | "conversation" | "topic" | "agent"} id={m[3]} label={m[1]} />)
    last = m.index + m[0].length
  }
  if (last < text.length) parts.push(...linkifyUrls(text.slice(last), `t${i++}`))
  return parts
}

// Walk a plain text fragment and turn bare URLs into clickable <a> tags.
// Matches http(s)://… and naked www.… (which we prefix with https). Trailing
// punctuation (period, comma, paren, bracket) is excluded from the link so
// "see https://x.com." doesn't capture the period.
const URL_RE = /\b(https?:\/\/[^\s<>"'`]+|www\.[^\s<>"'`]+)/g
const TRAILING_PUNCT_RE = /[.,;:!?)\]}>]+$/

function linkifyUrls(text: string, keyPrefix: string): ReactNode[] {
  const out: ReactNode[] = []
  let last = 0
  let m: RegExpExecArray | null
  let i = 0
  URL_RE.lastIndex = 0
  while ((m = URL_RE.exec(text)) !== null) {
    let url = m[0]
    let trailing = ""
    const trailMatch = url.match(TRAILING_PUNCT_RE)
    if (trailMatch) {
      trailing = trailMatch[0]
      url = url.slice(0, -trailing.length)
    }
    if (m.index > last) out.push(<Fragment key={`${keyPrefix}-pre${i}`}>{text.slice(last, m.index)}</Fragment>)
    const href = url.startsWith("www.") ? `https://${url}` : url
    out.push(
      <a
        key={`${keyPrefix}-a${i}`}
        href={href}
        target="_blank"
        rel="noopener noreferrer"
        className="underline decoration-accent/40 hover:decoration-accent text-accent break-all"
      >
        {url}
      </a>
    )
    if (trailing) out.push(<Fragment key={`${keyPrefix}-trail${i}`}>{trailing}</Fragment>)
    last = m.index + m[0].length
    i++
  }
  if (last < text.length) out.push(<Fragment key={`${keyPrefix}-tail`}>{text.slice(last)}</Fragment>)
  if (out.length === 0) out.push(<Fragment key={`${keyPrefix}-only`}>{text}</Fragment>)
  return out
}
