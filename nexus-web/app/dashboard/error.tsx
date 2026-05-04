"use client"

// Dashboard-wide error boundary. Catches any unhandled render error in any
// child route (operations, agents, map, etc.) so a single missing import or
// undefined ref doesn't blank the whole app like the map's "Users is not
// defined" did. Each child page can still ship its own error.tsx for a more
// tailored message; this is the catch-all fallback.

import { useEffect } from "react"
import { AlertTriangle, RefreshCw, ArrowLeft, Copy } from "lucide-react"
import Link from "next/link"
import { useState } from "react"

export default function DashboardError({
  error,
  reset,
}: {
  error: Error & { digest?: string }
  reset: () => void
}) {
  const [copied, setCopied] = useState(false)

  useEffect(() => {
    console.error("[Nexus] Dashboard crashed:", error)
  }, [error])

  const errorReport = [
    `Message: ${error.message || "(no message)"}`,
    error.digest ? `Digest:  ${error.digest}` : "",
    error.stack ? `\n${error.stack}` : "",
  ].filter(Boolean).join("\n")

  return (
    <div
      className="flex flex-col items-center justify-center min-h-[calc(100dvh-5rem)] md:min-h-screen p-6"
      style={{ background: "#03050f" }}
    >
      <div
        className="w-full max-w-2xl rounded-lg p-6"
        style={{
          background: "rgba(239,68,68,0.04)",
          border: "1px solid rgba(239,68,68,0.25)",
        }}
      >
        <div className="flex items-center justify-between mb-3" style={{ color: "#f87171" }}>
          <div className="flex items-center gap-2">
            <AlertTriangle size={16} />
            <span className="font-mono text-[10px] tracking-widest uppercase">
              Dashboard Render Failed
            </span>
          </div>
          <button
            onClick={() => {
              navigator.clipboard.writeText(errorReport)
              setCopied(true)
              setTimeout(() => setCopied(false), 1500)
            }}
            className="flex items-center gap-1 text-[10px] font-mono uppercase tracking-widest opacity-50 hover:opacity-100 transition-opacity"
          >
            <Copy size={10} /> {copied ? "Copied" : "Copy report"}
          </button>
        </div>

        <p className="text-sm font-semibold mb-2" style={{ color: "rgba(255,255,255,0.9)" }}>
          {error.message || "An unknown error occurred"}
        </p>

        {error.digest && (
          <p className="font-mono text-[10px] mb-3" style={{ color: "rgba(255,255,255,0.3)" }}>
            digest: {error.digest}
          </p>
        )}

        {error.stack && (
          <pre
            className="font-mono text-[10px] leading-relaxed overflow-x-auto p-3 rounded mb-4 whitespace-pre-wrap break-words"
            style={{
              background: "rgba(0,0,0,0.4)",
              color: "rgba(255,255,255,0.5)",
              maxHeight: 320,
            }}
          >
            {error.stack}
          </pre>
        )}

        <div className="flex gap-2">
          <button
            onClick={reset}
            className="flex items-center gap-1.5 px-3 py-1.5 text-[11px] font-medium rounded transition-colors"
            style={{
              background: "rgba(0,212,255,0.12)",
              border: "1px solid rgba(0,212,255,0.4)",
              color: "#00d4ff",
            }}
          >
            <RefreshCw size={11} /> Retry
          </button>
          <Link
            href="/dashboard"
            className="flex items-center gap-1.5 px-3 py-1.5 text-[11px] font-medium rounded transition-colors"
            style={{
              border: "1px solid rgba(255,255,255,0.15)",
              color: "rgba(255,255,255,0.6)",
            }}
          >
            <ArrowLeft size={11} /> Dashboard home
          </Link>
        </div>
      </div>
    </div>
  )
}
