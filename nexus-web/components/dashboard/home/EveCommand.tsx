"use client"

import { useCallback, useEffect, useRef, useState } from "react"
import Link from "next/link"
import { Send, Mic, Volume2, VolumeX, ArrowRight, Plus, Telescope, Sparkles, X } from "lucide-react"
import EveParticleFace from "@/components/dashboard/EveParticleFace"
import EveMessage from "@/components/dashboard/EveMessage"
import { useEveVoice } from "@/hooks/useEveVoice"
import MentionInput, { type MentionInputHandle } from "@/components/mentions/MentionInput"
import { renderPlainWithMentions } from "@/components/mentions/MentionRenderer"
import { stripMentionsToPlain } from "@/lib/mentions/parse"

type Citation = { url: string; title: string; snippet?: string }
type Message = { id: string; role: "user" | "assistant"; content: string; citations?: Citation[] }

type Props = {
  greeting: string
  suggestions: string[]
  lastConversation: {
    id: string
    title: string
    messages: Array<{ role: string; content: string; created_at: string }>
  } | null
  activeResearch: number
  onActivity: () => void
}

export default function EveCommand({ greeting, suggestions, lastConversation, activeResearch, onActivity }: Props) {
  const [conversationId, setConversationId] = useState<string | null>(lastConversation?.id ?? null)
  const [input, setInput] = useState("")
  const [messages, setMessages] = useState<Message[]>(() => {
    const base: Message[] = [{ id: "greeting", role: "assistant", content: greeting }]
    if (lastConversation?.messages?.length) {
      const tail = lastConversation.messages.slice(-2).map((m, i) => ({
        id: `tail-${i}`,
        role: m.role === "user" ? "user" as const : "assistant" as const,
        content: m.content,
      }))
      return [...base, ...tail]
    }
    return base
  })
  const [sending, setSending] = useState(false)
  const inputRef = useRef<MentionInputHandle>(null)
  const threadRef = useRef<HTMLDivElement>(null)

  const [sessionActive, setSessionActive] = useState(false)
  const [sessionInput, setSessionInput] = useState("")
  const [voiceEnabled, setVoiceEnabled] = useState(false)

  const [showNewOp, setShowNewOp] = useState(false)
  const [showNewRec, setShowNewRec] = useState(false)
  const [showResearch, setShowResearch] = useState(false)

  const handleVoiceTranscript = useCallback((text: string) => {
    submitRef.current(text)
  }, [])

  const {
    eveSpeaking, eveMuted, toggleEveMute, stopEve, speakAsEve,
    micActive, startMic, stopMic, pttStart, pttStop,
    voiceSupported, transcript, directorListening,
  } = useEveVoice(handleVoiceTranscript)

  useEffect(() => {
    threadRef.current?.scrollTo({ top: threadRef.current.scrollHeight, behavior: "smooth" })
  }, [messages, sending])

  // Escape key ends session
  useEffect(() => {
    if (!sessionActive) return
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") endSession() }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [sessionActive]) // eslint-disable-line react-hooks/exhaustive-deps

  const submitRef = useRef<(text: string) => Promise<void>>(async () => {})
  const submit = useCallback(async (text: string) => {
    const msg = text.trim()
    if (!msg || sending) return

    let convId = conversationId
    if (!convId) {
      const res = await fetch("/api/eve/conversations", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ title: msg.slice(0, 60) }),
      })
      if (!res.ok) return
      const data = await res.json()
      convId = data.conversation.id
      setConversationId(convId)
    }

    const userMsg: Message = { id: crypto.randomUUID(), role: "user", content: msg }
    setMessages(prev => [...prev.filter(m => m.id !== "greeting"), userMsg])
    setSending(true)

    try {
      const res = await fetch("/api/eve", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ userMessage: msg, conversationId: convId }),
      })
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const data = await res.json()
      const assistant: Message = {
        id: crypto.randomUUID(),
        role: "assistant",
        content: data.content ?? "",
        citations: data.citations ?? [],
      }
      setMessages(prev => [...prev, assistant])
      if ((voiceEnabled || sessionActive) && assistant.content) {
        speakAsEve(stripMentionsToPlain(assistant.content), "grok")
      }
      onActivity()
    } catch (err) {
      setMessages(prev => [...prev, {
        id: crypto.randomUUID(),
        role: "assistant",
        content: `System error: ${err instanceof Error ? err.message : "unknown"}`,
      }])
    } finally {
      setSending(false)
    }
  }, [conversationId, sending, voiceEnabled, sessionActive, speakAsEve, onActivity])
  submitRef.current = submit

  function onSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!input.trim()) return
    const t = input.trim()
    setInput("")
    inputRef.current?.clear()
    submit(t)
  }

  function onSessionSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!sessionInput.trim()) return
    const t = sessionInput.trim()
    setSessionInput("")
    submit(t)
  }

  const startSession = useCallback(() => {
    setSessionActive(true)
    setVoiceEnabled(true)
    startMic()
    if (greeting) setTimeout(() => speakAsEve(greeting, "grok"), 400)
  }, [greeting, startMic, speakAsEve])

  const endSession = useCallback(() => {
    setSessionActive(false)
    stopMic()
    stopEve()
    setVoiceEnabled(false)
  }, [stopMic, stopEve])

  const faceState: "speaking" | "loading" | "idle" =
    eveSpeaking ? "speaking" : sending ? "loading" : "idle"

  const sessionStatus =
    eveSpeaking ? "SPEAKING" :
    sending ? "PROCESSING" :
    directorListening ? "LISTENING" : "STANDBY"

  const sessionStatusColor =
    eveSpeaking ? "#00c8ff" :
    sending ? "#f59e0b" :
    directorListening ? "#22c55e" :
    "rgba(255,255,255,0.2)"

  return (
    <>
      {/* ── Session overlay ──────────────────────────────────────────────────── */}
      {sessionActive && (
        <>
          <style>{`
            @keyframes nexus-scan {
              0%   { transform: translateY(0);    opacity: 0; }
              8%   { opacity: 0.45; }
              92%  { opacity: 0.45; }
              100% { transform: translateY(480px); opacity: 0; }
            }
            @keyframes nexus-bracket-in {
              from { opacity: 0; transform: scale(1.06); }
              to   { opacity: 1; transform: scale(1); }
            }
            .nexus-bracket   { animation: nexus-bracket-in 0.5s ease-out forwards; }
            .nexus-scan-line {
              position: absolute; top: 0; left: 0; right: 0; height: 1px; pointer-events: none;
              background: linear-gradient(90deg, transparent, rgba(0,200,255,0.7), transparent);
              animation: nexus-scan 5s ease-in-out infinite;
            }
            @keyframes nexus-status-pulse {
              0%, 100% { opacity: 1; }
              50%       { opacity: 0.3; }
            }
            .nexus-status-dot-active { animation: nexus-status-pulse 1.2s ease-in-out infinite; }
          `}</style>

          <div
            className="fixed inset-0 z-50 flex flex-col select-none"
            style={{ background: "#000", fontFamily: "'SF Mono', 'Courier New', monospace" }}
          >
            {/* HUD top bar */}
            <div
              className="flex-none flex items-center justify-between px-8 py-3"
              style={{ borderBottom: "1px solid rgba(0,200,255,0.1)" }}
            >
              <div className="flex items-center gap-4">
                <span style={{ color: "#00c8ff", letterSpacing: "8px", fontSize: "12px", fontWeight: 300 }}>
                  NEXUS
                </span>
                <span style={{ color: "rgba(0,200,255,0.2)", fontSize: "10px" }}>◆</span>
                <span style={{ color: "rgba(255,255,255,0.3)", letterSpacing: "3px", fontSize: "9px" }}>
                  EVE COMMAND
                </span>
              </div>
              <div className="flex items-center gap-5">
                {activeResearch > 0 && (
                  <span className="flex items-center gap-1.5" style={{ color: "rgba(6,182,212,0.55)", fontSize: "9px", letterSpacing: "3px" }}>
                    <Telescope size={9} className="animate-pulse" />
                    {activeResearch} ACTIVE
                  </span>
                )}
                <button
                  onClick={endSession}
                  className="flex items-center gap-2 px-3 py-1 rounded transition-opacity hover:opacity-90"
                  style={{ border: "1px solid rgba(239,68,68,0.35)", color: "rgba(239,68,68,0.7)", fontSize: "9px", letterSpacing: "3px" }}
                >
                  <X size={9} />
                  END SESSION
                </button>
              </div>
            </div>

            {/* Main body */}
            <div className="flex-1 flex min-h-0">

              {/* Center — face + status */}
              <div className="flex-1 flex flex-col items-center justify-center gap-5 px-8">

                {/* Face with HUD chrome */}
                <div className="relative" style={{ width: 480, height: 480 }}>
                  {/* Corner brackets */}
                  <div className="nexus-bracket absolute top-0 left-0" style={{ width: 36, height: 36, borderTop: "1.5px solid rgba(0,200,255,0.5)", borderLeft: "1.5px solid rgba(0,200,255,0.5)" }} />
                  <div className="nexus-bracket absolute top-0 right-0" style={{ width: 36, height: 36, borderTop: "1.5px solid rgba(0,200,255,0.5)", borderRight: "1.5px solid rgba(0,200,255,0.5)" }} />
                  <div className="nexus-bracket absolute bottom-0 left-0" style={{ width: 36, height: 36, borderBottom: "1.5px solid rgba(0,200,255,0.5)", borderLeft: "1.5px solid rgba(0,200,255,0.5)" }} />
                  <div className="nexus-bracket absolute bottom-0 right-0" style={{ width: 36, height: 36, borderBottom: "1.5px solid rgba(0,200,255,0.5)", borderRight: "1.5px solid rgba(0,200,255,0.5)" }} />

                  {/* Scan line */}
                  <div className="nexus-scan-line" />

                  <EveParticleFace
                    speaking={faceState === "speaking"}
                    loading={faceState === "loading"}
                    size={480}
                    color="#00c8ff"
                  />
                </div>

                {/* Status indicator */}
                <div className="flex items-center gap-2.5">
                  <div
                    className={directorListening || eveSpeaking ? "nexus-status-dot-active" : ""}
                    style={{
                      width: 6, height: 6, borderRadius: "50%",
                      background: sessionStatusColor,
                      boxShadow: `0 0 8px ${sessionStatusColor}`,
                    }}
                  />
                  <span style={{ color: sessionStatusColor, letterSpacing: "5px", fontSize: "10px" }}>
                    {sessionStatus}
                  </span>
                </div>

                {/* Live transcript */}
                {transcript && (
                  <p style={{ color: "rgba(255,255,255,0.4)", fontSize: "13px", maxWidth: 420, textAlign: "center", fontStyle: "italic" }}>
                    &ldquo;{transcript}&rdquo;
                  </p>
                )}
              </div>

              {/* Right — transcript panel */}
              <div
                ref={threadRef}
                className="flex-none overflow-y-auto py-6 px-5 space-y-3"
                style={{ width: 320, borderLeft: "1px solid rgba(0,200,255,0.08)" }}
              >
                <div style={{ color: "rgba(0,200,255,0.35)", fontSize: "9px", letterSpacing: "4px", marginBottom: 12 }}>
                  TRANSCRIPT
                </div>
                {messages.slice(-10).map(m => (
                  <div key={m.id}>
                    {m.role === "user" ? (
                      <div className="flex justify-end">
                        <div
                          className="max-w-[85%] px-3 py-2 rounded text-[12px] leading-relaxed"
                          style={{ background: "rgba(255,255,255,0.05)", color: "rgba(255,255,255,0.65)" }}
                        >
                          {m.content}
                        </div>
                      </div>
                    ) : (
                      <div
                        className="text-[12px] leading-relaxed"
                        style={{ color: "rgba(0,200,255,0.75)" }}
                      >
                        {m.content.slice(0, 320)}{m.content.length > 320 ? "…" : ""}
                      </div>
                    )}
                  </div>
                ))}
                {sending && (
                  <div className="flex gap-1 pt-1">
                    {[0, 150, 300].map(d => (
                      <div key={d} className="w-1 h-1 rounded-full animate-bounce" style={{ background: "#00c8ff", animationDelay: `${d}ms` }} />
                    ))}
                  </div>
                )}
              </div>
            </div>

            {/* Bottom — text input */}
            <div style={{ borderTop: "1px solid rgba(0,200,255,0.1)" }}>
              <form onSubmit={onSessionSubmit} className="flex items-center gap-3 px-8 py-4">
                <input
                  type="text"
                  value={sessionInput}
                  onChange={e => setSessionInput(e.target.value)}
                  placeholder="Type a command…"
                  disabled={sending}
                  autoComplete="off"
                  className="flex-1 bg-transparent outline-none text-[13px] pb-1"
                  style={{
                    borderBottom: "1px solid rgba(0,200,255,0.2)",
                    color: "rgba(255,255,255,0.8)",
                    caretColor: "#00c8ff",
                  }}
                />
                <button
                  type="submit"
                  disabled={!sessionInput.trim() || sending}
                  style={{ color: "#00c8ff", opacity: sessionInput.trim() ? 1 : 0.25 }}
                >
                  <Send size={14} />
                </button>
              </form>
              <div className="px-8 pb-3 flex items-center gap-4" style={{ color: "rgba(255,255,255,0.18)", fontSize: "9px", letterSpacing: "3px" }}>
                <span>VOICE ACTIVE</span>
                <span>·</span>
                <span>SPEAK NATURALLY</span>
                <span>·</span>
                <span>ESC TO EXIT</span>
                {eveSpeaking && (
                  <>
                    <span>·</span>
                    <button onClick={stopEve} style={{ color: "rgba(239,68,68,0.6)" }}>STOP</button>
                  </>
                )}
              </div>
            </div>
          </div>
        </>
      )}

      {/* ── Normal command view ──────────────────────────────────────────────── */}
      <div className="flex flex-col p-5 lg:p-6 gap-0">

        {/* Eve face */}
        <div className="relative flex-none flex flex-col items-center">
          <div className="relative">
            <EveParticleFace
              speaking={faceState === "speaking"}
              loading={faceState === "loading"}
              size={300}
              color="#00c8ff"
            />
            {activeResearch > 0 && (
              <div
                className="absolute top-3 right-3 flex items-center gap-1.5 px-2.5 py-1 rounded-full font-mono text-[9px] uppercase tracking-widest border"
                style={{ color: "#06b6d4", borderColor: "rgba(6,182,212,0.35)", background: "rgba(6,182,212,0.08)" }}
              >
                <Telescope size={10} className="animate-pulse" />
                {activeResearch} active
              </div>
            )}
          </div>

          {/* Session + mute controls */}
          <div className="mt-4 flex items-center gap-2">
            <button
              onClick={startSession}
              className="flex items-center gap-2 px-5 py-2 rounded font-mono text-[10px] uppercase tracking-widest transition-all hover:opacity-90 active:scale-95"
              style={{
                border: "1px solid rgba(0,200,255,0.4)",
                color: "#00c8ff",
                background: "rgba(0,200,255,0.05)",
                letterSpacing: "4px",
              }}
            >
              <Mic size={10} />
              Initiate Session
            </button>
            <button
              onClick={toggleEveMute}
              className="p-2 rounded border transition-colors"
              style={{
                borderColor: eveMuted ? "rgba(239,68,68,0.4)" : "rgba(255,255,255,0.08)",
                color: eveMuted ? "#ef4444" : "rgba(255,255,255,0.35)",
              }}
              title={eveMuted ? "Unmute Eve" : "Mute Eve"}
            >
              {eveMuted ? <VolumeX size={12} /> : <Volume2 size={12} />}
            </button>
          </div>
        </div>

        {/* Rolling thread */}
        <div ref={threadRef} className="mt-5 max-h-[280px] overflow-y-auto pr-1 space-y-3">
          {messages.slice(-6).map(m => (
            <div key={m.id} className={m.role === "user" ? "flex justify-end" : ""}>
              {m.role === "user" ? (
                <div className="max-w-[80%] px-3 py-2 rounded-lg text-[13px] leading-relaxed bg-secondary text-foreground whitespace-pre-wrap">
                  {renderPlainWithMentions(m.content)}
                </div>
              ) : (
                <EveMessage content={m.content} citations={m.citations} />
              )}
            </div>
          ))}
          {sending && (
            <div className="flex items-center gap-2 text-[11px] font-mono text-muted-foreground">
              <span className="flex gap-1">
                <span className="w-1 h-1 rounded-full bg-accent animate-bounce" style={{ animationDelay: "0ms" }} />
                <span className="w-1 h-1 rounded-full bg-accent animate-bounce" style={{ animationDelay: "150ms" }} />
                <span className="w-1 h-1 rounded-full bg-accent animate-bounce" style={{ animationDelay: "300ms" }} />
              </span>
              Eve is thinking
            </div>
          )}
        </div>

        {/* Suggested follow-ups */}
        {suggestions.length > 0 && !sending && (
          <div className="flex-none mt-3 flex flex-wrap gap-1.5">
            {suggestions.map((s, i) => (
              <button
                key={i}
                onClick={() => submit(s)}
                className="flex items-center gap-1 px-2.5 py-1 rounded-full text-[11px] border border-border text-muted-foreground hover:text-foreground hover:border-accent/40 transition-colors"
              >
                <Sparkles size={10} className="text-accent/70" />
                {s}
              </button>
            ))}
          </div>
        )}

        {/* Text input */}
        <form onSubmit={onSubmit} className="flex-none mt-3">
          <div className="relative flex items-end gap-2">
            <MentionInput
              ref={inputRef}
              value={input}
              onChange={setInput}
              onSubmit={() => {
                if (input.trim()) {
                  const t = input
                  setInput("")
                  inputRef.current?.clear()
                  submit(t)
                }
              }}
              placeholder="Ask Eve anything… (@ to mention)"
              disabled={sending}
              minHeightClass="min-h-[42px]"
              maxHeightClass="max-h-[120px]"
              rightAdornment={
                <button
                  type="submit"
                  disabled={sending || !input.trim()}
                  className="absolute right-2 bottom-2 p-1.5 rounded-md text-accent hover:bg-accent/10 disabled:opacity-30 transition-colors"
                  aria-label="Send message"
                >
                  <Send size={15} />
                </button>
              }
            />
            {voiceSupported && (
              <button
                type="button"
                onMouseDown={pttStart}
                onMouseUp={pttStop}
                onMouseLeave={pttStop}
                onTouchStart={(e) => { e.preventDefault(); pttStart() }}
                onTouchEnd={(e) => { e.preventDefault(); pttStop() }}
                className="flex-none h-[42px] w-[42px] rounded-lg border flex items-center justify-center transition-colors"
                style={{
                  borderColor: micActive ? "rgba(239,68,68,0.5)" : "rgba(255,255,255,0.08)",
                  background: micActive ? "rgba(239,68,68,0.1)" : "transparent",
                  color: micActive ? "#ef4444" : "rgba(255,255,255,0.6)",
                }}
                aria-label="Hold to talk"
                title="Hold to talk"
              >
                <Mic size={15} className={micActive ? "animate-pulse" : ""} />
              </button>
            )}
          </div>
          <p className="mt-1.5 font-mono text-[9px] tracking-widest text-muted-foreground/60 uppercase">
            Enter to send · Hold mic to speak · @ to mention
          </p>
        </form>

        {/* Quick actions */}
        <div className="flex-none mt-4 pt-4 border-t border-border/60">
          <div className="flex items-center justify-between mb-2">
            <span className="font-mono text-[9px] uppercase tracking-widest text-muted-foreground">Quick Actions</span>
            {conversationId && (
              <Link
                href={`/dashboard/maxwell?c=${conversationId}`}
                className="flex items-center gap-1 text-[10px] font-mono uppercase tracking-widest text-accent/70 hover:text-accent transition-colors"
              >
                Full session <ArrowRight size={10} />
              </Link>
            )}
          </div>
          <div className="grid grid-cols-3 gap-2">
            <button
              onClick={() => setShowNewOp(true)}
              className="flex flex-col items-center gap-1 px-3 py-2.5 rounded-lg border border-border hover:border-amber-500/40 hover:bg-amber-500/5 transition-colors group"
            >
              <Plus size={14} className="text-amber-500/70 group-hover:text-amber-400" />
              <span className="text-[10px] text-muted-foreground group-hover:text-foreground">Operation</span>
            </button>
            <button
              onClick={() => setShowNewRec(true)}
              className="flex flex-col items-center gap-1 px-3 py-2.5 rounded-lg border border-border hover:border-yellow-500/40 hover:bg-yellow-500/5 transition-colors group"
            >
              <Plus size={14} className="text-yellow-500/70 group-hover:text-yellow-400" />
              <span className="text-[10px] text-muted-foreground group-hover:text-foreground">Record</span>
            </button>
            <button
              onClick={() => setShowResearch(true)}
              className="flex flex-col items-center gap-1 px-3 py-2.5 rounded-lg border border-border hover:border-cyan-500/40 hover:bg-cyan-500/5 transition-colors group"
            >
              <Telescope size={14} className="text-cyan-500/70 group-hover:text-cyan-400" />
              <span className="text-[10px] text-muted-foreground group-hover:text-foreground">Research</span>
            </button>
          </div>
        </div>

        {/* Quick prompt modals */}
        {showNewOp && (
          <QuickPromptModal
            title="New Operation"
            placeholder="e.g. Launch Q2 intel report on competitor X"
            submitLabel="Ask Eve to create"
            onClose={() => setShowNewOp(false)}
            onSubmit={(text) => { setShowNewOp(false); submit(`Create a new operation: ${text}`) }}
          />
        )}
        {showNewRec && (
          <QuickPromptModal
            title="New Record"
            placeholder="Describe the finding, note, or intel to save…"
            submitLabel="Save via Eve"
            onClose={() => setShowNewRec(false)}
            onSubmit={(text) => { setShowNewRec(false); submit(`Save this as a record: ${text}`) }}
          />
        )}
        {showResearch && (
          <QuickPromptModal
            title="Start Research"
            placeholder="What should Eve research? Be specific."
            submitLabel="Kick off research"
            onClose={() => setShowResearch(false)}
            onSubmit={(text) => { setShowResearch(false); submit(`Run research on: ${text}`) }}
          />
        )}
      </div>
    </>
  )
}

function QuickPromptModal({ title, placeholder, submitLabel, onClose, onSubmit }: {
  title: string
  placeholder: string
  submitLabel: string
  onClose: () => void
  onSubmit: (text: string) => void
}) {
  const [value, setValue] = useState("")
  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-background/80 backdrop-blur-sm"
      onClick={onClose}
    >
      <div
        className="w-full max-w-md bg-card border border-border rounded-xl p-5 shadow-2xl"
        onClick={e => e.stopPropagation()}
      >
        <h3 className="text-sm font-semibold mb-3">{title}</h3>
        <textarea
          autoFocus
          value={value}
          onChange={e => setValue(e.target.value)}
          placeholder={placeholder}
          rows={3}
          className="w-full px-3 py-2.5 rounded-lg bg-secondary border border-border focus:border-accent/50 outline-none text-sm resize-none"
        />
        <div className="flex justify-end gap-2 mt-3">
          <button
            onClick={onClose}
            className="text-[11px] font-mono uppercase tracking-widest px-3 py-1.5 rounded border border-border text-muted-foreground hover:text-foreground"
          >
            Cancel
          </button>
          <button
            onClick={() => value.trim() && onSubmit(value.trim())}
            disabled={!value.trim()}
            className="text-[11px] font-mono uppercase tracking-widest px-3 py-1.5 rounded bg-accent text-accent-foreground hover:bg-accent/90 disabled:opacity-40"
          >
            {submitLabel}
          </button>
        </div>
      </div>
    </div>
  )
}
