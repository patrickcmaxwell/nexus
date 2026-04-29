"use client"

// Route-level error boundary for the Nexus Map. Without this, a runtime
// crash during render is swallowed by v0's preview chrome as a generic
// "This page couldn't load" message with no actionable info. This surfaces
// the real error message + stack so we can actually debug.
import { useEffect } from "react"
import { AlertTriangle, RefreshCw, ArrowLeft } from "lucide-react"
import Link from "next/link"

export default function MapError({
  error,
  reset,
}: {
  error: Error & { digest?: string }
  reset: () => void
}) {
  useEffect(() => {
    // Surface the error to the server console so it shows up in v0 debug logs
    console.error("[v0] Nexus Map crashed:", error)
  }, [error])

  return (
    <div
      className="flex flex-col items-center justify-center min-h-[calc(100dvh-5rem)] md:min-h-screen p-6"
      style={{ background: "#03050f" }}
    >
      <div
        className="w-full max-w-lg rounded-lg p-6"
        style={{
          background: "rgba(239,68,68,0.04)",
          border: "1px solid rgba(239,68,68,0.25)",
        }}
      >
        <div className="flex items-center gap-2 mb-3" style={{ color: "#f87171" }}>
          <AlertTriangle size={16} />
          <span className="font-mono text-[10px] tracking-widest uppercase">
            Nexus Map Failed to Render
          </span>
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
              maxHeight: 280,
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
            <ArrowLeft size={11} /> Back to dashboard
          </Link>
        </div>
      </div>
    </div>
  )
}
