import { useCallback, useEffect, useRef, useState } from 'react'

export type EveStatus = 'idle' | 'listening' | 'thinking' | 'speaking'
export type ChatMessage = { id: string; role: 'user' | 'eve'; text: string; ts: number }

const NEXUS = 'http://localhost:3000'

async function callEve(
  message: string,
  convId: string | null,
  sessionId: string,
): Promise<{ content: string; conversationId: string }> {
  const res = await fetch(`${NEXUS}/api/eve`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${sessionId}` },
    body: JSON.stringify({ userMessage: message, conversationId: convId, source: 'desktop' }),
  })
  if (!res.ok) throw new Error(`Eve API ${res.status}`)
  return res.json()
}

async function callEveLocalWithImages(
  message: string,
  images: string[],
  convId: string | null,
  sessionId: string,
): Promise<{ content: string; conversationId: string | null }> {
  const res = await fetch(`${NEXUS}/api/eve/local`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${sessionId}` },
    body: JSON.stringify({
      userMessage: message || 'What do you see, Eve?',
      conversationId: convId,
      source: 'desktop',
      images,
    }),
  })
  if (!res.ok) throw new Error(`Eve local vision API ${res.status}`)
  return res.json()
}

function fileToBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onerror = () => reject(reader.error)
    reader.onload = () => {
      const out = String(reader.result || '')
      // Strip the "data:image/...;base64," prefix — server adds it back if missing
      const idx = out.indexOf(',')
      resolve(idx >= 0 ? out.slice(idx + 1) : out)
    }
    reader.readAsDataURL(file)
  })
}

async function playTTS(text: string, sessionId: string, audioRef: { current: HTMLAudioElement | null }): Promise<void> {
  try {
    const res = await fetch(`${NEXUS}/api/eve/tts`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${sessionId}` },
      body: JSON.stringify({ text }),
    })
    if (!res.ok) return
    const blob = await res.blob()
    const url  = URL.createObjectURL(blob)
    await new Promise<void>(resolve => {
      const audio = new Audio(url)
      audioRef.current?.pause()
      audioRef.current = audio
      let done = false
      const finish = () => { if (done) return; done = true; URL.revokeObjectURL(url); if (audioRef.current === audio) audioRef.current = null; resolve() }
      audio.onended = finish
      audio.onerror = finish
      audio.play().catch(finish)
      // Hard ceiling — never let the SPEAKING state hang forever
      setTimeout(finish, 45_000)
    })
  } catch { /* TTS failure is non-fatal — text already shown */ }
}

export function useEve(sessionId: string | null) {
  const [status, setStatus]               = useState<EveStatus>('idle')
  const [messages, setMessages]           = useState<ChatMessage[]>([])
  const [partial, setPartial]             = useState('')
  const [conversationId, setConversationId] = useState<string | null>(null)
  const [connected, setConnected]         = useState(false)
  const [pendingImages, setPendingImages] = useState<string[]>([])  // base64 strings

  const recogRef  = useRef<any>(null)
  const audioRef  = useRef<HTMLAudioElement | null>(null)
  const convIdRef = useRef<string | null>(null)

  convIdRef.current = conversationId

  const attachImage = useCallback(async (file: File) => {
    if (file.size > 5 * 1024 * 1024) { return }  // skip oversized
    try {
      const b64 = await fileToBase64(file)
      setPendingImages(imgs => [...imgs, b64])
    } catch { /* ignore */ }
  }, [])

  const clearPendingImages = useCallback(() => setPendingImages([]), [])

  // Poll nexus-web reachability
  useEffect(() => {
    if (!sessionId) { setConnected(false); return }
    const check = async () => {
      try {
        const r = await fetch(`${NEXUS}/api/dashboard/overview`, {
          headers: { Authorization: `Bearer ${sessionId}` },
          signal: AbortSignal.timeout(3000),
        })
        setConnected(r.ok)
      } catch { setConnected(false) }
    }
    check()
    const t = setInterval(check, 15_000)
    return () => clearInterval(t)
  }, [sessionId])

  const addMsg = useCallback((role: 'user' | 'eve', text: string) =>
    setMessages(m => [...m, { id: crypto.randomUUID(), role, text, ts: Date.now() }]), [])

  const send = useCallback(async (text: string) => {
    if (!sessionId || status === 'thinking') return
    // Cut off any prior TTS the moment the Director starts a new turn
    audioRef.current?.pause()
    audioRef.current = null

    // Vision branch — route through /api/eve/local + llava when images attached
    if (pendingImages.length > 0) {
      const imgs = pendingImages
      setPendingImages([])
      const label = text || '(image)'
      addMsg('user', `${label}  📷×${imgs.length}`)
      setStatus('thinking')
      try {
        const { content, conversationId: newId } = await callEveLocalWithImages(text, imgs, convIdRef.current, sessionId)
        if (newId && !convIdRef.current) {
          setConversationId(newId)
          convIdRef.current = newId
        }
        addMsg('eve', content)
        setStatus('speaking')
        await playTTS(content, sessionId, audioRef)
      } catch {
        addMsg('eve', 'Vision pipeline failed.')
      }
      setStatus('idle')
      return
    }

    addMsg('user', text)
    setStatus('thinking')
    try {
      const { content, conversationId: newId } = await callEve(text, convIdRef.current, sessionId)
      if (newId && !convIdRef.current) {
        setConversationId(newId)
        convIdRef.current = newId
      }
      addMsg('eve', content)
      setStatus('speaking')
      await playTTS(content, sessionId, audioRef)
    } catch {
      addMsg('eve', 'Unable to reach Nexus. Ensure nexus-web is running on port 3000.')
    }
    setStatus('idle')
  }, [sessionId, status, addMsg, pendingImages])

  const listen = useCallback(() => {
    if (status === 'thinking' || status === 'listening') return
    // Pressing mic while Eve is speaking interrupts her and starts listening
    audioRef.current?.pause()
    audioRef.current = null
    const SR = (window as any).SpeechRecognition ?? (window as any).webkitSpeechRecognition
    if (!SR) { alert('Speech recognition is not supported in this browser.'); return }

    const r = new SR()
    r.continuous      = false
    r.interimResults  = true
    r.lang            = 'en-US'
    recogRef.current  = r

    let transcript = ''
    setStatus('listening')

    r.onresult = (e: any) => {
      transcript = Array.from(e.results as any[])
        .map((res: any) => res[0].transcript)
        .join('')
      setPartial(transcript)
    }
    r.onend = () => {
      setPartial('')
      if (transcript.trim()) send(transcript.trim())
      else setStatus('idle')
    }
    r.onerror = () => { setPartial(''); setStatus('idle') }
    r.start()
  }, [status, send])

  const newConversation = useCallback(() => {
    recogRef.current?.abort()
    setMessages([])
    setConversationId(null)
    convIdRef.current = null
    setStatus('idle')
    setPartial('')
  }, [])

  const loadConversation = useCallback((
    raw: Array<{ role: string; content: string; ts?: string; created_at?: string }>,
    convId: string,
  ) => {
    const mapped: ChatMessage[] = raw.map(m => ({
      id: crypto.randomUUID(),
      role: m.role === 'user' ? 'user' : 'eve',
      text: m.content,
      ts: m.ts ? new Date(m.ts).getTime()
        : m.created_at ? new Date(m.created_at).getTime()
        : Date.now(),
    }))
    setMessages(mapped)
    setConversationId(convId)
    convIdRef.current = convId
    setStatus('idle')
    setPartial('')
  }, [])

  return {
    status, messages, partial, conversationId, connected,
    send, listen, newConversation, loadConversation,
    pendingImages, attachImage, clearPendingImages,
  }
}
