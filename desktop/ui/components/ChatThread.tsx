import React, { useEffect, useRef } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import type { ChatMessage } from '../hooks/useEve'

interface Props {
  messages: ChatMessage[]
  partial: string
}

export function ChatThread({ messages, partial }: Props) {
  const endRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    endRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages.length, partial])

  if (!messages.length && !partial) {
    return (
      <div className="flex-1 flex items-center justify-center pointer-events-none">
        <p className="text-[11px] font-mono tracking-[0.4em] text-white/10 uppercase">Speak or type to begin</p>
      </div>
    )
  }

  return (
    <div className="flex-1 overflow-y-auto no-scrollbar px-6 py-4 space-y-3">
      <AnimatePresence initial={false}>
        {messages.map(msg => (
          <motion.div
            key={msg.id}
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.2 }}
            className={`flex ${msg.role === 'user' ? 'justify-end' : 'justify-start'}`}
          >
            <div className={`max-w-[78%] px-4 py-3 rounded-2xl ${
              msg.role === 'user'
                ? 'bg-white/6 border border-white/10 rounded-tr-sm text-white/80'
                : 'border border-[#00d4ff]/15 bg-[#00d4ff]/5 rounded-tl-sm text-white/90'
            }`}>
              {msg.role === 'eve' && (
                <span className="text-[9px] font-mono text-[#00d4ff]/40 tracking-[0.3em] block mb-1.5 uppercase">Eve</span>
              )}
              <p className="text-sm leading-relaxed whitespace-pre-wrap select-text cursor-text">{msg.text}</p>
              <span className="text-[9px] font-mono text-white/20 mt-1.5 block text-right">
                {new Date(msg.ts).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
              </span>
            </div>
          </motion.div>
        ))}
      </AnimatePresence>

      {partial && (
        <motion.div className="flex justify-end" initial={{ opacity: 0 }} animate={{ opacity: 1 }}>
          <div className="max-w-[78%] px-4 py-3 rounded-2xl rounded-tr-sm bg-white/4 border border-white/8">
            <p className="text-sm text-white/40 italic">{partial}</p>
          </div>
        </motion.div>
      )}

      <div ref={endRef} />
    </div>
  )
}
