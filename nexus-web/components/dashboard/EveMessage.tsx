"use client"

import ReactMarkdown from "react-markdown"
import remarkGfm from "remark-gfm"
import { useState } from "react"
import { ExternalLink, BookmarkPlus, Check, Copy } from "lucide-react"
import { protectMentionsForMarkdown } from "@/lib/mentions/parse"
import { expandMentionsInChildren } from "@/components/mentions/MentionRenderer"

export type Citation = {
  url: string
  title: string
  snippet?: string
}

type Props = {
  content: string
  citations?: Citation[]
  isStreaming?: boolean
  onSaveToOperation?: (content: string, citations: Citation[]) => void
}

export default function EveMessage({ content, citations = [], isStreaming, onSaveToOperation }: Props) {
  const [savePanelOpen, setSavePanelOpen] = useState(false)
  const [operations, setOperations] = useState<Array<{ id: string; name: string }>>([])
  const [loadingOps, setLoadingOps] = useState(false)
  const [savingTo, setSavingTo] = useState<string | null>(null)
  const [saved, setSaved] = useState<string | null>(null)

  // Legacy: parse **Sources** block appended in older messages
  const sourceMatch = content.match(/\n\n\*\*Sources\*\*\n([\s\S]+)$/)
  const mainContent = sourceMatch ? content.slice(0, content.indexOf("\n\n**Sources**\n")) : content
  const legacySources: Citation[] = []

  if (sourceMatch) {
    const lines = sourceMatch[1].trim().split("\n")
    for (const line of lines) {
      const m = line.match(/^\d+\.\s+\[(.+?)\]\((.+?)\)/)
      if (m) legacySources.push({ title: m[1], url: m[2] })
    }
  }

  const allCitations = citations.length > 0 ? citations : legacySources

  // Protect @[label](type:id) tokens from being parsed as markdown links by
  // replacing them with zero-width sentinels. After ReactMarkdown renders we
  // walk the element tree and swap sentinels for live MentionChips.
  const protectedContent = protectMentionsForMarkdown(mainContent)

  async function openSavePanel() {
    setSavePanelOpen(true)
    if (operations.length > 0) return
    setLoadingOps(true)
    try {
      const res = await fetch("/api/operations")
      if (res.ok) {
        const data = await res.json()
        setOperations(data.operations ?? [])
      }
    } finally {
      setLoadingOps(false)
    }
  }

  async function saveToOperation(opId: string, opName: string) {
    setSavingTo(opId)
    try {
      // Build a summary: first 800 chars of content + source URLs
      const summary = content.slice(0, 800) + (content.length > 800 ? "…" : "")
      const sources = allCitations.map(c => `${c.title}: ${c.url}`).join("\n")
      const fullContent = sources ? `${summary}\n\nSources:\n${sources}` : summary

      await fetch("/api/operations/records", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          operation_id: opId,
          title: content.slice(0, 60).trim() + (content.length > 60 ? "…" : ""),
          content: fullContent,
          type: allCitations.length > 0 ? "intel" : "note",
          source: allCitations[0]?.url ?? "eve",
        }),
      })
      setSaved(opId)
      setTimeout(() => { setSaved(null); setSavePanelOpen(false) }, 1500)
      if (onSaveToOperation) onSaveToOperation(fullContent, allCitations)
    } finally {
      setSavingTo(null)
    }
  }

  return (
    <div className="flex flex-col gap-3">
      {/* Main markdown content */}
      <div className="prose prose-sm dark:prose-invert max-w-none leading-relaxed
        prose-headings:text-card-foreground prose-headings:font-semibold
        prose-h1:text-base prose-h2:text-sm prose-h3:text-sm
        prose-p:text-card-foreground prose-p:leading-relaxed prose-p:my-1.5
        prose-strong:text-card-foreground prose-strong:font-semibold
        prose-em:text-card-foreground/80
        prose-a:text-primary prose-a:no-underline hover:prose-a:underline
        prose-code:text-primary prose-code:bg-primary/10 prose-code:px-1 prose-code:py-0.5 prose-code:rounded prose-code:text-xs prose-code:font-mono prose-code:before:content-none prose-code:after:content-none
        prose-pre:bg-muted prose-pre:border prose-pre:border-border prose-pre:rounded-lg prose-pre:text-xs prose-pre:overflow-x-auto
        prose-ul:my-1.5 prose-ol:my-1.5
        prose-li:text-card-foreground prose-li:my-0.5 prose-li:marker:text-primary
        prose-blockquote:border-l-primary prose-blockquote:text-card-foreground/70
        prose-hr:border-border
        prose-img:rounded-lg prose-img:border prose-img:border-border prose-img:max-h-64 prose-img:object-cover
        prose-table:text-xs prose-th:text-card-foreground prose-td:text-card-foreground/80
      ">
        <ReactMarkdown
          remarkPlugins={[remarkGfm]}
          components={{
            // Each text-bearing component runs its children through the
            // sentinel expander so MENTION sentinels become real chips.
            p: ({ children }) => <p>{expandMentionsInChildren(children)}</p>,
            li: ({ children }) => <li>{expandMentionsInChildren(children)}</li>,
            strong: ({ children }) => <strong>{expandMentionsInChildren(children)}</strong>,
            em: ({ children }) => <em>{expandMentionsInChildren(children)}</em>,
            h1: ({ children }) => <h1>{expandMentionsInChildren(children)}</h1>,
            h2: ({ children }) => <h2>{expandMentionsInChildren(children)}</h2>,
            h3: ({ children }) => <h3>{expandMentionsInChildren(children)}</h3>,
            blockquote: ({ children }) => <blockquote>{expandMentionsInChildren(children)}</blockquote>,
            a: ({ href, children }) => (
              <a href={href} target="_blank" rel="noopener noreferrer">{expandMentionsInChildren(children)}</a>
            ),
            img: ({ src, alt }) => (
              <span className="block my-2">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={src} alt={alt ?? ""} className="rounded-lg border border-border max-h-64 object-cover w-full" />
                {alt && <span className="block text-[10px] text-muted-foreground mt-1 text-center">{alt}</span>}
              </span>
            ),
            pre: ({ children }) => <CodeBlock>{children}</CodeBlock>,
          }}
        >
          {protectedContent}
        </ReactMarkdown>
        {isStreaming && <span className="inline-block w-1.5 h-4 bg-accent/70 animate-pulse rounded-sm ml-0.5 align-middle" />}
      </div>

      {/* Citation / source cards */}
      {allCitations.length > 0 && (
        <div className="flex flex-col gap-2">
          <p className="text-[10px] text-muted-foreground uppercase tracking-widest font-medium">Sources</p>
          <div className="grid grid-cols-1 gap-2">
            {allCitations.map((c, i) => {
              let hostname = c.url
              try { hostname = new URL(c.url).hostname.replace("www.", "") } catch { /* noop */ }
              return (
                <a
                  key={i}
                  href={c.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex items-start gap-3 bg-muted/20 border border-border rounded-lg p-3 hover:border-accent/40 hover:bg-accent/5 transition-colors group"
                >
                  {/* Favicon */}
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img
                    src={`https://www.google.com/s2/favicons?domain=${hostname}&sz=32`}
                    alt=""
                    className="w-5 h-5 rounded flex-shrink-0 mt-0.5"
                    onError={(e) => { (e.target as HTMLImageElement).style.display = "none" }}
                  />
                  <div className="flex-1 min-w-0">
                    <p className="text-[12px] font-medium text-card-foreground group-hover:text-primary transition-colors leading-snug truncate">
                      {c.title !== c.url ? c.title : hostname}
                    </p>
                    {c.snippet && (
                      <p className="text-[11px] text-muted-foreground mt-0.5 leading-relaxed line-clamp-2">
                        {c.snippet}
                      </p>
                    )}
                    <p className="text-[10px] text-muted-foreground/50 mt-1 font-mono">{hostname}</p>
                  </div>
                  <ExternalLink size={12} className="text-muted-foreground/40 group-hover:text-accent/60 flex-shrink-0 mt-1 transition-colors" />
                </a>
              )
            })}
          </div>
        </div>
      )}

      {/* Save to Operation action */}
      <div className="flex items-center gap-2 pt-1">
        <button
          onClick={openSavePanel}
          className="flex items-center gap-2 text-xs font-semibold text-muted-foreground hover:text-primary transition-colors border border-border hover:border-primary/30 hover:bg-primary/5 rounded-lg px-3 py-1.5"
        >
          <BookmarkPlus size={13} />
          Save to operation
        </button>
      </div>

      {/* Save panel dropdown */}
      {savePanelOpen && (
        <div className="border border-border rounded-lg bg-card p-3 flex flex-col gap-2">
          <div className="flex items-center justify-between">
            <p className="text-[11px] font-semibold text-card-foreground">Save to Operation</p>
            <button onClick={() => setSavePanelOpen(false)} className="text-[11px] text-muted-foreground hover:text-card-foreground">✕</button>
          </div>
          {loadingOps ? (
            <div className="flex items-center justify-center py-3">
              <div className="w-4 h-4 border-2 border-accent border-t-transparent rounded-full animate-spin" />
            </div>
          ) : operations.length === 0 ? (
            <p className="text-[11px] text-muted-foreground text-center py-2">No operations found. Ask Eve to create one.</p>
          ) : (
            <div className="flex flex-col gap-1">
              {operations.map(op => (
                  <button
                    key={op.id}
                    onClick={() => saveToOperation(op.id, op.name)}
                    disabled={savingTo === op.id || saved === op.id}
                    className="flex items-center justify-between px-3 py-2 rounded-lg border border-border hover:border-primary/40 hover:bg-primary/5 text-[12px] text-card-foreground transition-colors disabled:opacity-60 text-left"
                  >
                  <span className="truncate">{op.name}</span>
                  {saved === op.id
                    ? <Check size={12} className="text-green-400 flex-shrink-0" />
                    : savingTo === op.id
                    ? <div className="w-3 h-3 border border-accent border-t-transparent rounded-full animate-spin flex-shrink-0" />
                    : null
                  }
                </button>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  )
}

function CodeBlock({ children }: { children: React.ReactNode }) {
  const [copied, setCopied] = useState(false)

  const getText = (node: React.ReactNode): string => {
    if (typeof node === "string") return node
    if (Array.isArray(node)) return node.map(getText).join("")
    if (node && typeof node === "object" && "props" in (node as { props?: unknown })) {
      return getText((node as React.ReactElement).props.children)
    }
    return ""
  }

  const handleCopy = () => {
    navigator.clipboard.writeText(getText(children)).then(() => {
      setCopied(true)
      setTimeout(() => setCopied(false), 1500)
    })
  }

  return (
    <div className="relative group">
      <pre className="overflow-x-auto">{children}</pre>
      <button
        onClick={handleCopy}
        className="absolute top-2 right-2 text-[10px] font-medium px-2 py-0.5 rounded bg-border/60 text-muted-foreground opacity-0 group-hover:opacity-100 hover:text-foreground transition-all flex items-center gap-1"
      >
        {copied ? <><Check size={10} /> Copied</> : <><Copy size={10} /> Copy</>}
      </button>
    </div>
  )
}
