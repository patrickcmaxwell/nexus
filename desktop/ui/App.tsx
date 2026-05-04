import React, { useEffect, useRef, useState } from 'react'
import { AnimatePresence } from 'framer-motion'
import { MessageSquare, Zap, Bot, Users, Shield, LogOut, Plus, Mic, MicOff, Send, LayoutDashboard, Image as ImageIcon, X } from 'lucide-react'
import { useEve } from './hooks/useEve'
import { PinAuth } from './views/PinAuth'
import { EveOrb } from './components/EveOrb'
import { ChatThread } from './components/ChatThread'
import { VoiceHUD } from './components/VoiceHUD'
import { DataPanel } from './components/DataPanel'
import { OpsView } from './views/OpsView'
import { AgentsView } from './views/AgentsView'
import { GroupsView } from './views/GroupsView'
import { DirectivesView } from './views/DirectivesView'
import { HistorySidebar } from './components/HistorySidebar'

type Section = 'eve' | 'ops' | 'agents' | 'groups' | 'directives'

const NAV: { id: Section; icon: React.ReactNode; label: string }[] = [
  { id: 'eve',        icon: <MessageSquare size={18} />, label: 'EVE' },
  { id: 'ops',        icon: <Zap size={18} />,           label: 'OPS' },
  { id: 'agents',     icon: <Bot size={18} />,           label: 'AGENTS' },
  { id: 'groups',     icon: <Users size={18} />,         label: 'GROUPS' },
  { id: 'directives', icon: <Shield size={18} />,        label: 'DIRECTIVES' },
]

export default function App() {
  const [sessionId, setSessionId]     = useState<string | null>(() => localStorage.getItem('nx_session'))
  const [section, setSection]         = useState<Section>('eve')
  const [showHistory, setShowHistory] = useState(false)
  const [showDataPanel, setShowDataPanel] = useState(false)
  const [input, setInput]             = useState('')
  const [hudVisible, setHudVisible]   = useState(false)
  const hudDismissRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  const eve = useEve(sessionId)

  const lastEveMessage = [...eve.messages].reverse().find(m => m.role === 'eve') ?? null

  // Only force the fullscreen HUD when the Director is actively using voice
  // (listening). Typed chat keeps the regular thread visible — the HUD is opt-in
  // via the orb / mic button.
  useEffect(() => {
    if (eve.status === 'listening') {
      if (hudDismissRef.current) clearTimeout(hudDismissRef.current)
      setHudVisible(true)
    } else if (eve.status === 'idle') {
      hudDismissRef.current = setTimeout(() => setHudVisible(false), 2000)
    }
    return () => { if (hudDismissRef.current) clearTimeout(hudDismissRef.current) }
  }, [eve.status])

  function handleAuth(id: string) {
    localStorage.setItem('nx_session', id)
    setSessionId(id)
  }

  function logout() {
    localStorage.removeItem('nx_session')
    setSessionId(null)
  }

  function handleSend() {
    const text = input.trim()
    // Allow empty text if images are attached (vision-only request)
    if ((!text && eve.pendingImages.length === 0) || eve.status === 'thinking') return
    setInput('')
    eve.send(text)
  }

  if (!sessionId) return <PinAuth onAuth={handleAuth} />

  const busy = eve.status === 'thinking'

  return (
    <div className="h-screen w-screen bg-[#030303] flex overflow-hidden text-foreground font-sans">

      {/* ── Left nav rail ──────────────────────────────────────────────── */}
      <div className="flex-shrink-0 w-16 flex flex-col items-center py-4 gap-1 border-r border-white/[0.04] bg-black/40">
        <div className="w-10 h-10 rounded-xl border border-white/10 flex items-center justify-center mb-4"
          style={{ boxShadow: '0 0 20px rgba(0,212,255,0.1)' }}>
          <span className="text-[9px] font-mono text-[#00d4ff]/70 tracking-widest">NX</span>
        </div>

        {NAV.map(n => (
          <button
            key={n.id}
            onClick={() => setSection(n.id)}
            title={n.label}
            className={`w-10 h-10 rounded-xl flex flex-col items-center justify-center gap-0.5 transition-all ${
              section === n.id
                ? 'bg-[#00d4ff]/10 text-[#00d4ff] border border-[#00d4ff]/20'
                : 'text-white/25 hover:text-white/60 hover:bg-white/5'
            }`}
          >
            {n.icon}
          </button>
        ))}

        <div className="flex-1" />

        <div className={`w-2 h-2 rounded-full mb-1 ${eve.connected ? 'bg-[#00ff88]' : 'bg-red-500'}`}
          title={eve.connected ? 'Nexus online' : 'Nexus offline'} />

        <button onClick={logout} title="Logout"
          className="w-10 h-10 rounded-xl flex items-center justify-center text-white/20 hover:text-red-400/60 hover:bg-white/5 transition-all">
          <LogOut size={16} />
        </button>
      </div>

      {/* ── Main content ────────────────────────────────────────────────── */}
      <div className="flex-1 flex overflow-hidden relative">

        {/* Voice HUD overlay */}
        <AnimatePresence>
          {hudVisible && (
            <VoiceHUD
              status={eve.status}
              connected={eve.connected}
              partial={eve.partial}
              lastEveMessage={lastEveMessage}
              onDismiss={() => setHudVisible(false)}
            />
          )}
        </AnimatePresence>

        {/* History sidebar (EVE section only) */}
        <AnimatePresence>
          {section === 'eve' && showHistory && sessionId && (
            <HistorySidebar
              sessionId={sessionId}
              onClose={() => setShowHistory(false)}
              onNew={() => { eve.newConversation(); setShowHistory(false) }}
              onLoad={(messages, convId) => {
                eve.loadConversation(messages, convId)
                setShowHistory(false)
              }}
            />
          )}
        </AnimatePresence>

        {/* EVE section */}
        {section === 'eve' && (
          <div className="flex-1 flex overflow-hidden">
            <div className="flex-1 flex flex-col overflow-hidden">

              {/* Top bar */}
              <div className="flex items-center justify-between px-5 py-2.5 border-b border-white/[0.04] flex-shrink-0">
                <div className="flex items-center gap-2">
                  <span className="text-[10px] font-mono tracking-[0.4em] text-white/20 uppercase">Eve Intelligence</span>
                  <div className={`flex items-center gap-1 px-2 py-0.5 rounded-full border text-[9px] font-mono uppercase tracking-widest ${
                    eve.connected ? 'border-[#00ff88]/20 text-[#00ff88]/60' : 'border-red-500/20 text-red-400/60'
                  }`}>
                    <span className={`w-1 h-1 rounded-full ${eve.connected ? 'bg-[#00ff88]' : 'bg-red-400'}`} />
                    {eve.connected ? 'NEXUS LIVE' : 'NEXUS OFFLINE'}
                  </div>
                </div>
                <div className="flex items-center gap-1">
                  <button onClick={() => setShowHistory(v => !v)}
                    className={`text-[10px] font-mono px-2.5 py-1 border rounded-lg transition-colors ${
                      showHistory ? 'text-[#00d4ff]/80 border-[#00d4ff]/20' : 'text-white/25 border-white/8 hover:text-white/60 hover:border-white/20'
                    }`}>
                    HISTORY
                  </button>
                  <button onClick={eve.newConversation}
                    className="flex items-center gap-1.5 text-[10px] font-mono text-white/25 hover:text-white/60 px-2.5 py-1 border border-white/8 hover:border-white/20 rounded-lg transition-colors">
                    <Plus size={11} /> NEW
                  </button>
                  <button onClick={() => setShowDataPanel(v => !v)} title="Data Panel"
                    className={`flex items-center justify-center w-7 h-7 rounded-lg border transition-colors ml-1 ${
                      showDataPanel ? 'text-[#00d4ff]/80 border-[#00d4ff]/20 bg-[#00d4ff]/8' : 'text-white/25 border-white/8 hover:text-white/60 hover:border-white/20'
                    }`}>
                    <LayoutDashboard size={12} />
                  </button>
                </div>
              </div>

              {/* Orb */}
              <div className="flex justify-center pt-5 pb-2 flex-shrink-0 cursor-pointer"
                onClick={() => {
                  if (eve.status === 'idle') { eve.listen(); setHudVisible(true) }
                  else setHudVisible(true)
                }}
                title="Click to speak to EVE"
              >
                <EveOrb status={eve.status} connected={eve.connected} />
              </div>

              {/* Chat */}
              <ChatThread messages={eve.messages} partial={eve.partial} />

              {/* Input */}
              <div className="flex-shrink-0 px-6 pb-5 pt-3 border-t border-white/[0.04]"
                onDragOver={e => { e.preventDefault() }}
                onDrop={e => {
                  e.preventDefault()
                  for (const file of Array.from(e.dataTransfer.files)) {
                    if (file.type.startsWith('image/')) eve.attachImage(file)
                  }
                }}
              >
                {/* Pending images strip */}
                {eve.pendingImages.length > 0 && (
                  <div className="flex items-center gap-2 mb-2 px-3 py-1.5 bg-[#00d4ff]/8 border border-[#00d4ff]/25 rounded-xl">
                    <ImageIcon size={11} className="text-[#00d4ff]/80" />
                    <span className="text-[10px] font-mono tracking-widest text-[#00d4ff]/80 uppercase">
                      Vision · {eve.pendingImages.length} image{eve.pendingImages.length === 1 ? '' : 's'}
                    </span>
                    <span className="flex-1" />
                    <button onClick={eve.clearPendingImages}
                      className="flex items-center gap-1 text-[9px] font-mono text-white/40 hover:text-white/70">
                      <X size={9} /> CLEAR
                    </button>
                  </div>
                )}
                <div className="flex items-center gap-2 bg-white/4 border border-white/8 rounded-2xl px-4 py-2.5 focus-within:border-white/15 transition-colors">
                  <button onClick={() => { eve.listen(); setHudVisible(true) }} disabled={busy}
                    className={`flex-shrink-0 w-8 h-8 rounded-xl flex items-center justify-center transition-all ${
                      eve.status === 'listening'
                        ? 'bg-[#00ff88]/15 text-[#00ff88] border border-[#00ff88]/30'
                        : busy ? 'text-white/15 cursor-not-allowed'
                        : 'text-white/30 hover:text-white/60 hover:bg-white/5'
                    }`}>
                    {eve.status === 'listening' ? <Mic size={15} /> : <MicOff size={15} />}
                  </button>
                  <label
                    title="Attach image — Eve uses llava (vision)"
                    className={`flex-shrink-0 w-8 h-8 rounded-xl flex items-center justify-center cursor-pointer transition-all ${
                      eve.pendingImages.length > 0
                        ? 'bg-[#00d4ff]/15 text-[#00d4ff] border border-[#00d4ff]/30'
                        : 'text-white/30 hover:text-white/60 hover:bg-white/5'
                    }`}>
                    <ImageIcon size={14} />
                    <input type="file" accept="image/*" multiple className="hidden"
                      onChange={e => {
                        for (const f of Array.from(e.target.files ?? [])) eve.attachImage(f)
                        e.currentTarget.value = ''
                      }}
                    />
                  </label>
                  <input
                    value={input}
                    onChange={e => setInput(e.target.value)}
                    onKeyDown={e => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); handleSend() } }}
                    placeholder={
                      eve.status === 'listening' ? 'Listening...' :
                      eve.status === 'thinking'  ? 'Processing...' :
                      eve.pendingImages.length > 0 ? 'Ask about the image...' :
                      'Command Eve...'
                    }
                    disabled={busy}
                    className="flex-1 bg-transparent text-sm text-white/80 placeholder:text-white/18 focus:outline-none disabled:opacity-40"
                  />
                  <button onClick={handleSend} disabled={(!input.trim() && eve.pendingImages.length === 0) || busy}
                    className="flex-shrink-0 w-8 h-8 rounded-xl flex items-center justify-center text-white/30 hover:text-[#00d4ff] hover:bg-[#00d4ff]/10 disabled:opacity-20 disabled:cursor-not-allowed transition-all">
                    <Send size={14} />
                  </button>
                </div>
                {eve.partial && (
                  <p className="text-[10px] font-mono text-white/20 mt-1.5 px-4 truncate">
                    <span className="text-[#00ff88]/40">●</span> {eve.partial}
                  </p>
                )}
              </div>
            </div>

            {/* Data panel (right side of EVE view) */}
            <AnimatePresence>
              {showDataPanel && sessionId && (
                <DataPanel sessionId={sessionId} onClose={() => setShowDataPanel(false)} />
              )}
            </AnimatePresence>
          </div>
        )}

        {section === 'ops'        && <OpsView        sessionId={sessionId} />}
        {section === 'agents'     && <AgentsView     sessionId={sessionId} />}
        {section === 'groups'     && <GroupsView     sessionId={sessionId} />}
        {section === 'directives' && <DirectivesView sessionId={sessionId} />}
      </div>
    </div>
  )
}
