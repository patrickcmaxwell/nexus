import React from 'react'
import { motion } from 'framer-motion'
import type { EveStatus } from '../hooks/useEve'

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

interface Props { status: EveStatus; connected: boolean }

export function EveOrb({ status, connected }: Props) {
  const c = connected ? COLOR[status] : '#ff4444'
  const isActive = status !== 'idle' && connected

  return (
    <div className="flex flex-col items-center gap-5 select-none py-2">
      <div className="relative w-40 h-40 flex items-center justify-center">

        {/* Pulse rings — listening / speaking */}
        {(status === 'listening' || status === 'speaking') && connected && [0, 1].map(i => (
          <motion.div
            key={i}
            className="absolute rounded-full border"
            style={{ borderColor: c, width: 160, height: 160 }}
            animate={{ scale: [1, 1.6 + i * 0.4], opacity: [0.5, 0] }}
            transition={{ duration: 1.4, repeat: Infinity, delay: i * 0.4, ease: 'easeOut' }}
          />
        ))}

        {/* Thinking arc */}
        {status === 'thinking' && connected && (
          <motion.div
            className="absolute rounded-full border-2 border-transparent"
            style={{ borderTopColor: c, borderRightColor: c + '44', width: 168, height: 168 }}
            animate={{ rotate: 360 }}
            transition={{ duration: 1.1, repeat: Infinity, ease: 'linear' }}
          />
        )}

        {/* Inner glow ring */}
        <motion.div
          className="absolute rounded-full"
          style={{ width: 136, height: 136, border: `1px solid ${c}44` }}
          animate={{ opacity: isActive ? [0.4, 0.8, 0.4] : [0.15, 0.25, 0.15] }}
          transition={{ duration: isActive ? 1.2 : 3, repeat: Infinity, ease: 'easeInOut' }}
        />

        {/* Core orb */}
        <motion.div
          className="w-28 h-28 rounded-full flex items-center justify-center relative overflow-hidden"
          style={{
            background: `radial-gradient(circle at 38% 32%, ${c}18, #030303 70%)`,
            boxShadow: `0 0 ${isActive ? 60 : 30}px ${c}${isActive ? '55' : '25'}, 0 0 ${isActive ? 120 : 60}px ${c}${isActive ? '22' : '10'}`,
            border: `1px solid ${c}${isActive ? '55' : '22'}`,
          }}
          animate={{
            boxShadow: isActive
              ? [`0 0 50px ${c}44`, `0 0 80px ${c}66`, `0 0 50px ${c}44`]
              : [`0 0 20px ${c}18`, `0 0 35px ${c}22`, `0 0 20px ${c}18`],
          }}
          transition={{ duration: isActive ? 1.5 : 4, repeat: Infinity, ease: 'easeInOut' }}
        >
          {/* Scanline shimmer */}
          <motion.div
            className="absolute inset-0 opacity-10"
            style={{ background: `linear-gradient(135deg, transparent 40%, ${c}66 50%, transparent 60%)` }}
            animate={{ x: ['-100%', '200%'] }}
            transition={{ duration: 3, repeat: Infinity, ease: 'linear', repeatDelay: 2 }}
          />
          <span className="text-[11px] font-mono tracking-[0.35em] uppercase z-10" style={{ color: c }}>EVE</span>
        </motion.div>
      </div>

      {/* Status */}
      <div className="flex items-center gap-2">
        <motion.div
          className="w-1.5 h-1.5 rounded-full"
          style={{ background: c }}
          animate={{ opacity: isActive ? [1, 0.3, 1] : [0.4, 0.7, 0.4] }}
          transition={{ duration: isActive ? 0.8 : 2.5, repeat: Infinity }}
        />
        <span className="text-[10px] font-mono tracking-[0.35em] uppercase" style={{ color: c }}>
          {connected ? LABEL[status] : 'OFFLINE'}
        </span>
      </div>
    </div>
  )
}
