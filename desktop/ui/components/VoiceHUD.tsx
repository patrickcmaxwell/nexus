import React, { useRef } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import type { EveStatus, ChatMessage } from '../hooks/useEve'

const COLOR: Record<EveStatus, string> = {
  idle:      'rgba(255,255,255,0.18)',
  listening: '#00ff88',
  thinking:  '#ffb800',
  speaking:  '#00d4ff',
}
const LABEL: Record<EveStatus, string> = {
  idle:      'STANDBY',
  listening: 'LISTENING',
  thinking:  'PROCESSING',
  speaking:  'SPEAKING',
}

const BAR_COUNT = 40

function peakHeight(i: number, total: number): number {
  const center = (total - 1) / 2
  const dist = Math.abs(i - center) / center
  return (1 - dist * 0.55) * 52 + 6
}

interface Props {
  status: EveStatus
  connected: boolean
  partial: string
  lastEveMessage: ChatMessage | null
  onDismiss: () => void
}

export function VoiceHUD({ status, connected, partial, lastEveMessage, onDismiss }: Props) {
  const c          = connected ? COLOR[status] : '#ff4444'
  const isActive   = connected && status !== 'idle'
  const isListening = status === 'listening' && connected
  const isThinking  = status === 'thinking'  && connected
  const isSpeaking  = status === 'speaking'  && connected
  const showBars   = isListening || isSpeaking

  const displayText = isListening
    ? partial
    : (lastEveMessage?.text ?? '')

  const bars = Array.from({ length: BAR_COUNT }, (_, i) => i)

  return (
    <motion.div
      className="fixed inset-0 z-50 flex flex-col items-center justify-center select-none"
      style={{ background: 'rgba(2,2,2,0.96)', backdropFilter: 'blur(8px)' }}
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      transition={{ duration: 0.25 }}
    >

      {/* ── Corner brackets ──────────────────────────────────────────────── */}
      {(['tl','tr','bl','br'] as const).map(pos => (
        <div key={pos} className="absolute" style={{
          top: pos.startsWith('t') ? 24 : undefined,
          bottom: pos.startsWith('b') ? 24 : undefined,
          left: pos.endsWith('l') ? 24 : undefined,
          right: pos.endsWith('r') ? 24 : undefined,
        }}>
          <div className="w-9 h-9" style={{
            borderTop:    pos.startsWith('t') ? `2px solid ${c}55` : undefined,
            borderBottom: pos.startsWith('b') ? `2px solid ${c}55` : undefined,
            borderLeft:   pos.endsWith('l')   ? `2px solid ${c}55` : undefined,
            borderRight:  pos.endsWith('r')   ? `2px solid ${c}55` : undefined,
          }} />
        </div>
      ))}

      {/* ── Top metadata row ─────────────────────────────────────────────── */}
      <div className="absolute top-9 flex items-center gap-8">
        <span className="text-[9px] font-mono tracking-[0.55em] uppercase" style={{ color: `${c}55` }}>
          EVE INTELLIGENCE
        </span>
        <div className="w-px h-3 bg-white/10" />
        <span className="text-[9px] font-mono tracking-[0.55em] uppercase" style={{ color: `${c}35` }}>
          {connected ? 'NEXUS LIVE' : 'NEXUS OFFLINE'}
        </span>
      </div>

      {/* ── Main orb ─────────────────────────────────────────────────────── */}
      <div className="relative flex items-center justify-center mb-10" style={{ width: 320, height: 320 }}>

        {/* Outer pulse rings */}
        {(isListening || isSpeaking) && [0, 1, 2].map(i => (
          <motion.div key={i} className="absolute rounded-full border"
            style={{ borderColor: `${c}35`, width: 320, height: 320 }}
            animate={{ scale: [1, 1.35 + i * 0.22], opacity: [0.55, 0] }}
            transition={{ duration: 1.7, repeat: Infinity, delay: i * 0.48, ease: 'easeOut' }}
          />
        ))}

        {/* Thinking arcs */}
        {isThinking && [0, 1].map(i => (
          <motion.div key={i} className="absolute rounded-full"
            style={{
              width: 310 + i * 32, height: 310 + i * 32,
              border: '2px solid transparent',
              borderTopColor: i === 0 ? c : `${c}55`,
              borderRightColor: i === 0 ? `${c}44` : 'transparent',
            }}
            animate={{ rotate: i === 0 ? 360 : -360 }}
            transition={{ duration: 1.1 + i * 0.5, repeat: Infinity, ease: 'linear' }}
          />
        ))}

        {/* Mid glow ring */}
        <motion.div className="absolute rounded-full"
          style={{ width: 256, height: 256, border: `1px solid ${c}35` }}
          animate={{ opacity: isActive ? [0.3, 0.75, 0.3] : [0.1, 0.2, 0.1] }}
          transition={{ duration: isActive ? 1.3 : 3.5, repeat: Infinity }}
        />

        {/* Core orb */}
        <motion.div
          className="relative rounded-full flex items-center justify-center overflow-hidden"
          style={{
            width: 208, height: 208,
            background: `radial-gradient(circle at 36% 30%, ${c}22, #020202 72%)`,
            border: `1px solid ${c}${isActive ? '66' : '33'}`,
            boxShadow: `0 0 90px ${c}${isActive ? '55' : '28'}, 0 0 200px ${c}${isActive ? '28' : '12'}`,
          }}
          animate={{
            boxShadow: isActive
              ? [`0 0 80px ${c}44`, `0 0 130px ${c}77`, `0 0 80px ${c}44`]
              : [`0 0 50px ${c}22`, `0 0 80px ${c}33`, `0 0 50px ${c}22`],
          }}
          transition={{ duration: isActive ? 1.4 : 4, repeat: Infinity }}
        >
          <motion.div className="absolute inset-0 opacity-12"
            style={{ background: `linear-gradient(135deg, transparent 40%, ${c}77 50%, transparent 60%)` }}
            animate={{ x: ['-100%', '200%'] }}
            transition={{ duration: 2.8, repeat: Infinity, ease: 'linear', repeatDelay: 1.2 }}
          />
          <span className="text-2xl font-mono tracking-[0.45em] z-10 uppercase" style={{ color: c }}>
            EVE
          </span>
        </motion.div>
      </div>

      {/* ── Status label ─────────────────────────────────────────────────── */}
      <div className="flex items-center gap-4 mb-9">
        <motion.div className="w-2 h-2 rounded-full" style={{ background: c }}
          animate={{ opacity: isActive ? [1, 0.15, 1] : [0.4, 0.7, 0.4] }}
          transition={{ duration: isActive ? 0.65 : 2.5, repeat: Infinity }}
        />
        <span className="text-[13px] font-mono tracking-[0.6em] uppercase" style={{ color: c }}>
          {connected ? LABEL[status] : 'OFFLINE'}
        </span>
        <motion.div className="w-2 h-2 rounded-full" style={{ background: c }}
          animate={{ opacity: isActive ? [1, 0.15, 1] : [0.4, 0.7, 0.4] }}
          transition={{ duration: isActive ? 0.65 : 2.5, repeat: Infinity, delay: 0.32 }}
        />
      </div>

      {/* ── Voice waveform ────────────────────────────────────────────────── */}
      <AnimatePresence>
        {showBars && (
          <motion.div className="flex items-end gap-[2.5px] h-16 mb-9"
            initial={{ opacity: 0, scaleY: 0 }}
            animate={{ opacity: 1, scaleY: 1 }}
            exit={{ opacity: 0, scaleY: 0 }}
            transition={{ duration: 0.3 }}
          >
            {bars.map(i => {
              const peak = peakHeight(i, BAR_COUNT)
              const dur  = isSpeaking ? 0.22 + (i % 7) * 0.06 : 0.5 + (i % 5) * 0.1
              return (
                <motion.div key={i}
                  className="rounded-full"
                  style={{ width: 3, background: c, opacity: 0.75 }}
                  animate={{ height: [4, peak, peak * 0.4, peak * 0.8, 4] }}
                  transition={{ duration: dur, repeat: Infinity, delay: (i / BAR_COUNT) * 0.9, ease: 'easeInOut' }}
                />
              )
            })}
          </motion.div>
        )}
      </AnimatePresence>

      {/* ── Transcript / response text ────────────────────────────────────── */}
      <AnimatePresence mode="wait">
        {displayText ? (
          <motion.div key="text" className="max-w-2xl px-12 text-center"
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -8 }}
            transition={{ duration: 0.3 }}
          >
            <p className="text-[15px] font-mono leading-loose" style={{ color: `${c}90` }}>
              {displayText}
            </p>
          </motion.div>
        ) : (
          <motion.div key="empty" className="h-10"
            initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
          />
        )}
      </AnimatePresence>

      {/* ── Dismiss ───────────────────────────────────────────────────────── */}
      <button onClick={onDismiss}
        className="absolute bottom-9 text-[9px] font-mono tracking-[0.5em] uppercase transition-all hover:opacity-60 active:scale-95"
        style={{ color: `${c}45` }}
      >
        TAP TO COLLAPSE
      </button>
    </motion.div>
  )
}
