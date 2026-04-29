"use client"

import { useCallback, useEffect, useRef, useState } from "react"

export type MicMode = "vad" | "ptt"
export type TtsMode = "grok" | "system"

export type EveVoiceState = {
  eveSpeaking: boolean
  eveMuted: boolean
  toggleEveMute: () => void
  stopEve: () => void
  speakAsEve: (text: string, mode?: TtsMode) => void
  ttsError: string | null
  directorListening: boolean
  directorMuted: boolean
  toggleDirectorMute: () => void
  micActive: boolean
  startMic: () => void
  stopMic: () => void
  pttStart: () => void
  pttStop: () => void
  pttActive: boolean
  voiceSupported: boolean
  transcript: string
}

// How long (ms) of silence after last speech before auto-submitting in VAD mode.
// 900ms feels natural — long enough to finish a sentence, short enough to feel responsive.
const VAD_SUBMIT_DELAY_MS = 900

export function useEveVoice(onTranscriptFinal: (text: string) => void): EveVoiceState {
  const audioRef = useRef<HTMLAudioElement | null>(null)
  const audioUrlRef = useRef<string | null>(null)
  const recognitionRef = useRef<any>(null)

  // All mutable state that callbacks read — stored in refs to prevent stale closures
  const eveMutedRef = useRef(false)
  const eveSpeakingRef = useRef(false)
  const directorMutedRef = useRef(false)
  const micModeRef = useRef<MicMode>("vad")
  const pttActiveRef = useRef(false)
  const onTranscriptRef = useRef(onTranscriptFinal)
  const isStoppedRef = useRef(false)

  // VAD submit timer — fires after VAD_SUBMIT_DELAY_MS of silence
  const vadTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  // Accumulated transcript across multiple isFinal events within one utterance
  const accumulatedRef = useRef("")
  // Restart-after-end timer
  const restartTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  // Keep callback ref current without rebuilding recognition
  useEffect(() => { onTranscriptRef.current = onTranscriptFinal }, [onTranscriptFinal])

  const [eveSpeaking, setEveSpeaking] = useState(false)
  const [eveMuted, setEveMuted] = useState(false)
  const [ttsError, setTtsError] = useState<string | null>(null)
  const [directorListening, setDirectorListening] = useState(false)
  const [directorMuted, setDirectorMuted] = useState(false)
  const [micMode, setMicModeState] = useState<MicMode>("vad")
  const [pttActive, setPttActive] = useState(false)
  const [micActive, setMicActive] = useState(false)
  const [transcript, setTranscript] = useState("")
  const [voiceSupported, setVoiceSupported] = useState(false)

  // ── TTS stop helper — defined before recognition so it can be called inside onresult ──
  const stopEve = useCallback(() => {
    if (audioRef.current) {
      audioRef.current.pause()
      audioRef.current.src = ""
      audioRef.current = null
    }
    if (audioUrlRef.current) {
      URL.revokeObjectURL(audioUrlRef.current)
      audioUrlRef.current = null
    }
    if (typeof window !== "undefined" && window.speechSynthesis) {
      window.speechSynthesis.cancel()
    }
    eveSpeakingRef.current = false
    setEveSpeaking(false)
  }, [])

  const stopEveRef = useRef(stopEve)
  useEffect(() => { stopEveRef.current = stopEve }, [stopEve])

  // ── Build SpeechRecognition ONCE on mount ───────────────────────────────────
  useEffect(() => {
    const SpeechRecognition =
      (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition
    if (!SpeechRecognition) return
    setVoiceSupported(true)

    const rec = new SpeechRecognition()
    rec.continuous = true
    rec.interimResults = true
    rec.lang = "en-US"
    recognitionRef.current = rec

    rec.onresult = (event: any) => {
      let interim = ""
      let finalChunk = ""

      for (let i = event.resultIndex; i < event.results.length; i++) {
        const t = event.results[i][0].transcript
        if (event.results[i].isFinal) {
          finalChunk += t
        } else {
          interim += t
        }
      }

      // Removed: Automatic interruption of Eve has been disabled to prevent
      // her from interrupting herself when the microphone picks up her TTS audio.
      // if ((interim || finalChunk) && eveSpeakingRef.current) {
      //   stopEveRef.current()
      // }

      if (micModeRef.current === "ptt") {
        // PTT: show live transcript, submit on pttStop
        setTranscript(interim || finalChunk)
        if (finalChunk.trim()) {
          accumulatedRef.current += " " + finalChunk.trim()
        }
        return
      }

      // VAD mode: accumulate finals, show interim live
      if (finalChunk.trim()) {
        accumulatedRef.current += " " + finalChunk.trim()
      }
      setTranscript((accumulatedRef.current + " " + interim).trim())

      // Reset the submit timer on every speech event — only fires after silence
      if (vadTimerRef.current) clearTimeout(vadTimerRef.current)

      if (accumulatedRef.current.trim()) {
        vadTimerRef.current = setTimeout(() => {
          const text = accumulatedRef.current.trim()
          accumulatedRef.current = ""
          setTranscript("")
          if (text) onTranscriptRef.current(text)
        }, VAD_SUBMIT_DELAY_MS)
      }
    }

    rec.onstart = () => setDirectorListening(true)

    rec.onend = () => {
      setDirectorListening(false)
      // Auto-restart only if mic was explicitly started and not stopped
      if (
        micModeRef.current === "vad" &&
        !directorMutedRef.current &&
        !isStoppedRef.current
      ) {
        if (restartTimerRef.current) clearTimeout(restartTimerRef.current)
        restartTimerRef.current = setTimeout(() => {
          if (!isStoppedRef.current && !directorMutedRef.current && micModeRef.current === "vad") {
            try { rec.start() } catch { /* already running */ }
          }
        }, 200)
      }
    }

    rec.onerror = (e: any) => {
      if (e.error === "not-allowed" || e.error === "service-not-allowed") {
        setVoiceSupported(false)
        return
      }
      // Transient errors: schedule restart
      if (micModeRef.current === "vad" && !directorMutedRef.current && !isStoppedRef.current) {
        if (restartTimerRef.current) clearTimeout(restartTimerRef.current)
        restartTimerRef.current = setTimeout(() => {
          if (!isStoppedRef.current && !directorMutedRef.current) {
            try { rec.start() } catch { /* ignore */ }
          }
        }, 800)
      }
    }

    // Do NOT auto-start — mic only starts when user explicitly enables it
    isStoppedRef.current = true

    return () => {
      isStoppedRef.current = true
      if (vadTimerRef.current) clearTimeout(vadTimerRef.current)
      if (restartTimerRef.current) clearTimeout(restartTimerRef.current)
      try { rec.stop() } catch { /* ignore */ }
    }
  }, []) // Empty deps — refs handle all mutable state

  // ── TTS ────────────────────────────────────────────────────────────────────
  function speakFallback(text: string) {
    if (typeof window === "undefined" || !window.speechSynthesis) {
      setTtsError("No TTS available")
      return
    }
    window.speechSynthesis.cancel()
    function doSpeak() {
      const utt = new SpeechSynthesisUtterance(text)
      utt.rate = 0.95
      utt.pitch = 1.05
      utt.volume = 1.0
      const voices = window.speechSynthesis.getVoices()
      const female = voices.find(v =>
        /samantha|karen|victoria|moira|fiona|zira|female|google us english/i.test(v.name)
      )
      if (female) utt.voice = female
      utt.onstart = () => { eveSpeakingRef.current = true; setEveSpeaking(true) }
      utt.onend = () => { eveSpeakingRef.current = false; setEveSpeaking(false) }
      utt.onerror = () => { eveSpeakingRef.current = false; setEveSpeaking(false) }
      window.speechSynthesis.speak(utt)
    }
    const voices = window.speechSynthesis.getVoices()
    if (voices.length > 0) doSpeak()
    else window.speechSynthesis.addEventListener("voiceschanged", doSpeak, { once: true })
  }

  const speakAsEve = useCallback(async (text: string, mode: TtsMode = "grok") => {
    if (eveMutedRef.current) return
    stopEve()
    setTtsError(null)

    if (mode === "system") { speakFallback(text); return }

    // Cap at 600 chars — TTS generation time scales with length
    const trimmed = text.replace(/\*\*|__|\*|_|`|#{1,6}\s/g, "").slice(0, 600).trim()

    try {
      const res = await fetch("/api/eve/tts", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text: trimmed }),
      })

      if (!res.ok) {
        const err = await res.json().catch(() => ({ error: `HTTP ${res.status}` }))
        console.error("[v0] TTS error:", err)
        setTtsError(err.error ?? "TTS failed")
        speakFallback(trimmed)
        return
      }

      const blob = await res.blob()
      if (blob.size === 0) {
        console.error("[v0] TTS returned empty blob")
        speakFallback(trimmed)
        return
      }

      const blobUrl = URL.createObjectURL(blob)
      audioUrlRef.current = blobUrl

      const audio = new Audio(blobUrl)
      audioRef.current = audio

      // Explicitly stop microphone to prevent feedback loop (Half-Duplex)
      if (micModeRef.current === "vad" && !isStoppedRef.current) {
        try { recognitionRef.current?.stop() } catch { /* ignore */ }
      }

      audio.onplay = () => { eveSpeakingRef.current = true; setEveSpeaking(true) }
      audio.onended = () => {
        eveSpeakingRef.current = false
        setEveSpeaking(false)
        URL.revokeObjectURL(blobUrl)
        audioUrlRef.current = null

        // Resume mic after she finishes talking
        if (micModeRef.current === "vad" && !directorMutedRef.current && !isStoppedRef.current) {
          try { recognitionRef.current?.start() } catch { /* ignore */ }
        }
      }
      audio.onerror = (e) => {
        console.error("[v0] Audio playback error:", e)
        eveSpeakingRef.current = false
        setEveSpeaking(false)
        URL.revokeObjectURL(blobUrl)
        audioUrlRef.current = null
        speakFallback(trimmed)
      }

      await audio.play()
    } catch (err) {
      console.error("[v0] speakAsEve error:", err)
      speakFallback(trimmed)
    }
  }, [stopEve])

  const toggleEveMute = useCallback(() => {
    const next = !eveMutedRef.current
    eveMutedRef.current = next
    setEveMuted(next)
    if (next) stopEve()
  }, [stopEve])

  // ── Mic controls ───────────────────────────────────────────────────────────
  const toggleDirectorMute = useCallback(() => {
    const next = !directorMutedRef.current
    directorMutedRef.current = next
    setDirectorMuted(next)
    if (next) {
      // Muting — stop mic
      isStoppedRef.current = true
      if (vadTimerRef.current) clearTimeout(vadTimerRef.current)
      if (restartTimerRef.current) clearTimeout(restartTimerRef.current)
      accumulatedRef.current = ""
      setTranscript("")
      try { recognitionRef.current?.stop() } catch { /* ignore */ }
      setDirectorListening(false)
    } else {
      // Unmuting — explicitly start mic
      isStoppedRef.current = false
      if (micModeRef.current === "vad") {
        try { recognitionRef.current?.start() } catch { /* ignore */ }
      }
    }
  }, [stopEve])

  const setMicMode = useCallback((mode: MicMode) => {
    micModeRef.current = mode
    setMicModeState(mode)
    setPttActive(false)
    pttActiveRef.current = false
    if (vadTimerRef.current) clearTimeout(vadTimerRef.current)
    accumulatedRef.current = ""
    setTranscript("")

    if (mode === "ptt") {
      isStoppedRef.current = true
      if (restartTimerRef.current) clearTimeout(restartTimerRef.current)
      try { recognitionRef.current?.stop() } catch { /* ignore */ }
    } else {
      // Switching to VAD — resume
      isStoppedRef.current = false
      if (!directorMutedRef.current) {
        try { recognitionRef.current?.start() } catch { /* ignore */ }
      }
    }
  }, [])

  // Explicit mic on/off — called by UI mic button
  const startMic = useCallback(() => {
    if (!recognitionRef.current) return
    directorMutedRef.current = false
    setDirectorMuted(false)
    isStoppedRef.current = false
    setMicActive(true)
    accumulatedRef.current = ""
    setTranscript("")
    try { recognitionRef.current.start() } catch { /* already running */ }
  }, [])

  const stopMic = useCallback(() => {
    isStoppedRef.current = true
    if (vadTimerRef.current) clearTimeout(vadTimerRef.current)
    if (restartTimerRef.current) clearTimeout(restartTimerRef.current)
    accumulatedRef.current = ""
    setTranscript("")
    setMicActive(false)
    setDirectorListening(false)
    try { recognitionRef.current?.stop() } catch { /* ignore */ }
  }, [])

  const pttStart = useCallback(() => {
    if (directorMutedRef.current || micModeRef.current !== "ptt") return
    pttActiveRef.current = true
    setPttActive(true)
    stopEve() // Interrupt Eve when PTT pressed
    accumulatedRef.current = ""
    setTranscript("")
    isStoppedRef.current = false
    try { recognitionRef.current?.start() } catch { /* already started */ }
  }, [stopEve])

  const pttStop = useCallback(() => {
    if (micModeRef.current !== "ptt") return
    pttActiveRef.current = false
    setPttActive(false)
    isStoppedRef.current = true
    try { recognitionRef.current?.stop() } catch { /* ignore */ }
    // Submit whatever was accumulated
    const text = accumulatedRef.current.trim()
    accumulatedRef.current = ""
    setTranscript("")
    if (text) onTranscriptRef.current(text)
  }, [])

  return {
    eveSpeaking, eveMuted, toggleEveMute, stopEve, speakAsEve, ttsError,
    directorListening, directorMuted, toggleDirectorMute,
    micActive, startMic, stopMic,
    pttStart, pttStop, pttActive,
    voiceSupported, transcript,
  }
}
