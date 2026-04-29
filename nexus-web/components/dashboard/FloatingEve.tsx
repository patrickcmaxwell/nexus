"use client"

import { useState, useRef, useEffect, useCallback } from "react"
import { MessageSquare, X, Minus, Send, Volume2, VolumeX, ChevronDown, ExternalLink } from "lucide-react"
import { useEveVoice } from "@/hooks/useEveVoice"
import { useTheme } from "@/hooks/useTheme"
import Link from "next/link"
import dynamic from "next/dynamic"
import { stripMentionsToPlain } from "@/lib/mentions/parse"

const EveParticleFace = dynamic(() => import("@/components/dashboard/EveParticleFace"), { ssr: false })

type Message = {
  id: string
  role: "user" | "assistant"
  content: string
}

const WELCOME: Message = {
  id: "welcome",
  role: "assistant",
  content: "Eve online. How can I assist, sir?",
}

// Animated audio waveform bars shown when Eve is speaking
function AudioWaveform({ color = "#00d4ff" }: { color?: string }) {
  return (
    <span className="flex gap-0.5 items-end h-3.5 ml-1">
      {[0.6, 1, 0.7, 0.9, 0.5, 0.8, 0.6].map((h, i) => (
        <span
          key={i}
          className="w-0.5 rounded-full"
          style={{
            background: color,
            height: `${Math.round(h * 14)}px`,
            animationName: "eveWave",
            animationDuration: `${0.5 + i * 0.07}s`,
            animationTimingFunction: "ease-in-out",
            animationIterationCount: "infinite",
            animationDirection: "alternate",
            animationDelay: `${i * 0.06}s`,
            opacity: 0.85,
          }}
        />
      ))}
    </span>
  )
}

export default function FloatingEve() {
  const { resolved } = useTheme()
  const [open, setOpen] = useState(false)
  const [minimized, setMinimized] = useState(false)
  const [messages, setMessages] = useState<Message[]>([WELCOME])
  const [input, setInput] = useState("")
  const [isLoading, setIsLoading] = useState(false)
  const [voiceEnabled, setVoiceEnabled] = useState(false)
  const voiceEnabledRef = useRef(false)
  voiceEnabledRef.current = voiceEnabled
  const [ttsMode, setTtsMode] = useState<"grok" | "system">("grok")
  const [pulse, setPulse] = useState(false)
  const [activeConvId, setActiveConvId] = useState<string | null>(null)
  const [convTitle, setConvTitle] = useState<string | null>(null)
  const messagesEndRef = useRef<HTMLDivElement>(null)
  const inputRef = useRef<HTMLInputElement>(null)
  
  // Theme-aware colors
  const accentColor = resolved.isSimple ? "oklch(0.55 0.20 250)" : "#00d4ff"
  const bgColor = resolved.isDark ? "rgba(5,8,18,0.97)" : resolved.isSimple ? "rgba(255,255,255,0.97)" : "rgba(5,8,18,0.97)"
  const borderColor = resolved.isDark || resolved.isFuturistic ? "rgba(0,200,255,0.18)" : "rgba(0,0,0,0.08)"
  const textColor = resolved.isDark ? "rgba(255,255,255,0.85)" : "rgba(0,0,0,0.85)"
  const mutedColor = resolved.isDark ? "rgba(255,255,255,0.2)" : "rgba(0,0,0,0.3)"

  const handleVoiceTranscript = useCallback((text: string) => {
    submitMessage(text)
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  const { eveSpeaking, stopEve, speakAsEve } = useEveVoice(handleVoiceTranscript)

  // Poll localStorage for active conversation from MaxwellClient
  useEffect(() => {
    function syncConv() {
      const convId = localStorage.getItem("nx_active_conv")
      if (convId && convId !== activeConvId) {
        setActiveConvId(convId)
        // Load recent messages from that conversation
        fetch(`/api/eve/history?conversationId=${convId}&limit=20`)
          .then(r => r.json())
          .then(d => {
            const msgs: Message[] = (d.messages ?? []).map((h: { id: string; role: string; content: string }) => ({
              id: h.id,
              role: h.role as "user" | "assistant",
              content: h.content,
            }))
            if (msgs.length > 0) {
              setMessages(msgs.slice(-12)) // last 12 messages for context
              const lastConvTitle = d.title ?? null
              setConvTitle(lastConvTitle)
            }
          })
          .catch(() => {})
      }
    }

    syncConv()
    const interval = setInterval(syncConv, 2000)
    return () => clearInterval(interval)
  }, [activeConvId])

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" })
  }, [messages, isLoading])

  useEffect(() => {
    if (open && !minimized) setTimeout(() => inputRef.current?.focus(), 100)
  }, [open, minimized])

  async function submitMessage(text: string) {
    if (!text.trim() || isLoading) return
    const userMsg: Message = { id: crypto.randomUUID(), role: "user", content: text }
    setMessages(prev => [...prev.filter(m => m.id !== "welcome"), userMsg])
    setIsLoading(true)
    setInput("")

    try {
      const res = await fetch("/api/eve", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ userMessage: text, conversationId: activeConvId }),
      })
      const data = await res.json()
      const content = data.content ?? "..."

      // If a new conversation was created, track it
      if (data.conversationId && !activeConvId) {
        setActiveConvId(data.conversationId)
        localStorage.setItem("nx_active_conv", data.conversationId)
      }

      const assistantMsg: Message = { id: crypto.randomUUID(), role: "assistant", content }
      setMessages(prev => [...prev, assistantMsg])
      if (voiceEnabledRef.current) speakAsEve(stripMentionsToPlain(content), ttsMode)

      if (!open || minimized) {
        setPulse(true)
        setTimeout(() => setPulse(false), 3000)
      }
    } catch {
      setMessages(prev => [...prev, { id: crypto.randomUUID(), role: "assistant", content: "System error, sir." }])
    } finally {
      setIsLoading(false)
    }
  }

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    submitMessage(input.trim())
  }

  return (
    <>
      {/* Floating trigger — particle face orb */}
      {!open && (
        <button
          onClick={() => { setOpen(true); setMinimized(false) }}
          className="fixed bottom-20 md:bottom-6 right-4 md:right-6 z-50 flex flex-col items-center gap-1.5 transition-all duration-300"
          style={{ filter: pulse ? "drop-shadow(0 0 20px rgba(0,200,255,0.6))" : "drop-shadow(0 0 8px rgba(0,200,255,0.2))" }}
          aria-label="Open Eve"
        >
          {/* Particle face orb */}
          <div className="relative rounded-full overflow-hidden"
            style={{
              width: 64, height: 64,
              border: `2px solid ${pulse ? "rgba(0,200,255,0.7)" : "rgba(0,200,255,0.25)"}`,
              boxShadow: pulse
                ? "0 0 32px rgba(0,200,255,0.5), 0 0 64px rgba(0,200,255,0.2)"
                : "0 0 16px rgba(0,200,255,0.15)",
              background: "rgba(5,8,18,0.95)",
              transition: "border-color 0.3s, box-shadow 0.3s",
            }}
          >
            <EveParticleFace speaking={eveSpeaking} size={64} />
            {pulse && (
              <span className="absolute top-1 right-1 w-2 h-2 rounded-full"
                style={{ background: "#00c8ff", boxShadow: "0 0 8px #00c8ff" }}
              />
            )}
          </div>
          {/* Name label */}
          <div className="flex items-center gap-1.5 px-2.5 py-1 rounded-full"
            style={{
              background: "rgba(5,8,18,0.9)",
              border: "1px solid rgba(0,200,255,0.2)",
            }}
          >
            <span className="w-1 h-1 rounded-full bg-emerald-400" style={{ boxShadow: "0 0 4px #34d399" }} />
            <span className="text-[10px] font-bold tracking-wider" style={{ color: "rgba(0,200,255,0.9)" }}>EVE</span>
                  {eveSpeaking && <AudioWaveform color={accentColor} />}
          </div>
        </button>
      )}

      {/* Chat panel */}
      {open && (
        <div
          className="fixed bottom-20 md:bottom-6 right-4 md:right-6 z-50 flex flex-col"
          style={{
            width: "min(380px, calc(100vw - 32px))",
            height: minimized ? "auto" : "min(540px, calc(100vh - 160px))",
            background: bgColor,
            border: `1px solid ${borderColor}`,
            borderRadius: 20,
            boxShadow: resolved.isDark 
              ? "0 24px 80px rgba(0,0,0,0.7), 0 0 40px rgba(0,200,255,0.06)"
              : "0 24px 80px rgba(0,0,0,0.15), 0 8px 30px rgba(0,0,0,0.1)",
            overflow: "hidden",
            backdropFilter: "blur(24px)",
            WebkitBackdropFilter: "blur(24px)",
          }}
        >
          {/* Header — particle face + name */}
          <div
            className="flex items-center justify-between px-4 py-3 flex-none"
            style={{ borderBottom: minimized ? "none" : "1px solid rgba(0,200,255,0.08)" }}
          >
            <div className="flex items-center gap-3 min-w-0 flex-1">
              {/* Inline particle face — small */}
              <div className="relative flex-shrink-0 rounded-full overflow-hidden"
                style={{
                  width: 38, height: 38,
                  border: `1.5px solid ${eveSpeaking ? "rgba(0,200,255,0.6)" : "rgba(0,200,255,0.2)"}`,
                  boxShadow: eveSpeaking ? "0 0 16px rgba(0,200,255,0.4)" : "none",
                  transition: "border-color 0.3s, box-shadow 0.3s",
                  background: "rgba(5,8,18,1)",
                }}
              >
                <EveParticleFace speaking={eveSpeaking} loading={isLoading} size={38} />
              </div>
              <div className="min-w-0">
                <div className="flex items-center gap-1.5">
                  <span className="text-[13px] font-bold tracking-wide" style={{ color: textColor }}>Eve</span>
                  {eveSpeaking && <AudioWaveform color={accentColor} />}
                </div>
                {convTitle && !eveSpeaking && (
                  <span className="text-[10px] truncate block font-mono" style={{ color: mutedColor }}>
                    {convTitle}
                  </span>
                )}
                {!convTitle && !eveSpeaking && (
                  <span className="text-[10px]" style={{ color: "rgba(52,211,153,0.7)" }}>Online</span>
                )}
              </div>
            </div>

            <div className="flex items-center gap-1 flex-none ml-2">
              {/* Voice toggle */}
              <button
                onClick={() => { const n = !voiceEnabled; voiceEnabledRef.current = n; setVoiceEnabled(n); if (!n) stopEve() }}
                className="p-1.5 rounded transition-colors"
                style={{ color: voiceEnabled ? "rgba(0,212,255,0.9)" : "rgba(255,255,255,0.2)" }}
                title={voiceEnabled ? "Voice ON" : "Voice OFF"}
              >
                {voiceEnabled ? <Volume2 size={12} /> : <VolumeX size={12} />}
              </button>

              {/* Mode switcher */}
              {voiceEnabled && (
                <button
                  onClick={() => setTtsMode(m => m === "grok" ? "system" : "grok")}
                  className="text-[9px] px-1.5 py-0.5 rounded border font-medium transition-colors"
                  style={{
                    color: ttsMode === "grok" ? "rgba(0,212,255,0.9)" : "rgba(255,255,255,0.35)",
                    borderColor: ttsMode === "grok" ? "rgba(0,212,255,0.35)" : "rgba(255,255,255,0.12)",
                  }}
                  title={ttsMode === "grok" ? "Grok Eve voice" : "System voice"}
                >
                  {ttsMode === "grok" ? "Grok" : "Sys"}
                </button>
              )}

              {/* Open in Eve full page */}
              {activeConvId && (
                <Link
                  href={`/dashboard/maxwell?c=${activeConvId}`}
                  className="p-1.5 rounded transition-colors"
                  style={{ color: "rgba(255,255,255,0.2)" }}
                  title="Open full conversation"
                >
                  <ExternalLink size={12} />
                </Link>
              )}

              <button onClick={() => setMinimized(!minimized)} className="p-1.5 rounded" style={{ color: mutedColor }}>
                {minimized ? <ChevronDown size={12} style={{ transform: "rotate(180deg)" }} /> : <Minus size={12} />}
              </button>
              <button onClick={() => setOpen(false)} className="p-1.5 rounded" style={{ color: mutedColor }}>
                <X size={12} />
              </button>
            </div>
          </div>

          {/* Messages + Input */}
          {!minimized && (
            <>
              <div className="flex-1 overflow-y-auto px-4 py-3 flex flex-col gap-2.5">
                {messages.map(msg => (
                  <div key={msg.id} className={`flex ${msg.role === "user" ? "justify-end" : "justify-start"}`}>
                    <div
                      className="max-w-[88%] px-3 py-2 text-[12px] leading-relaxed"
                      style={{
                        borderRadius: msg.role === "user" ? "12px 12px 2px 12px" : "12px 12px 12px 2px",
                        background: msg.role === "user" 
                          ? (resolved.isDark ? "rgba(0,212,255,0.1)" : "rgba(0,100,200,0.08)")
                          : (resolved.isDark ? "rgba(255,255,255,0.04)" : "rgba(0,0,0,0.03)"),
                        border: msg.role === "user" 
                          ? (resolved.isDark ? "1px solid rgba(0,212,255,0.18)" : "1px solid rgba(0,100,200,0.15)")
                          : (resolved.isDark ? "1px solid rgba(255,255,255,0.07)" : "1px solid rgba(0,0,0,0.06)"),
                        color: textColor,
                      }}
                    >
                      {msg.content}
                    </div>
                  </div>
                ))}

                {isLoading && (
                  <div className="flex justify-start">
                    <div className="px-3 py-2.5 flex items-center gap-1.5"
                      style={{
                        borderRadius: "12px 12px 12px 2px",
                        background: resolved.isDark ? "rgba(255,255,255,0.04)" : "rgba(0,0,0,0.03)",
                        border: resolved.isDark ? "1px solid rgba(255,255,255,0.07)" : "1px solid rgba(0,0,0,0.06)",
                      }}>
                      {[0, 1, 2].map(i => (
                        <span key={i} className="w-1 h-1 rounded-full"
                          style={{ background: accentColor, animation: `pulse 1.2s ease-in-out ${i * 0.2}s infinite` }} />
                      ))}
                    </div>
                  </div>
                )}
                <div ref={messagesEndRef} />
              </div>

              <form
                onSubmit={handleSubmit}
                className="flex-none flex items-center gap-2 px-3 py-2.5"
                style={{ borderTop: resolved.isDark ? "1px solid rgba(255,255,255,0.06)" : "1px solid rgba(0,0,0,0.06)" }}
              >
                <input
                  ref={inputRef}
                  value={input}
                  onChange={e => setInput(e.target.value)}
                  placeholder="Message Eve..."
                  disabled={isLoading}
                  className="flex-1 bg-transparent text-[12px] focus:outline-none"
                  style={{ color: textColor, opacity: 1 }}
                />
                <button
                  type="submit"
                  disabled={!input.trim() || isLoading}
                  className="p-1.5 rounded transition-colors disabled:opacity-30"
                  style={{ color: "rgba(0,212,255,0.8)" }}
                >
                  <Send size={13} />
                </button>
              </form>
            </>
          )}
        </div>
      )}

      <style>{`
        @keyframes eveWave {
          from { transform: scaleY(0.4); opacity: 0.5; }
          to   { transform: scaleY(1);   opacity: 1;   }
        }
      `}</style>
    </>
  )
}
