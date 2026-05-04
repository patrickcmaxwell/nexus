import React from 'react'
import { motion } from 'framer-motion'

type VoiceState = 'idle' | 'listening' | 'thinking' | 'speaking'

export function VoiceVisualizer({ state }: { state: VoiceState }) {
  const getNumBars = () => {
    switch (state) {
      case 'idle': return 3
      case 'listening': return 5
      case 'thinking': return 4
      case 'speaking': return 7
    }
  }

  const bars = Array.from({ length: getNumBars() })

  return (
    <div className="flex items-center gap-1.5 h-16 px-6 rounded-full bg-border/20 backdrop-blur-md border border-border/50">
      {bars.map((_, i) => (
        <motion.div
          key={i}
          className="w-1.5 rounded-full bg-primary"
          animate={{
            height: state === 'idle' ? 4 : state === 'listening' ? [12, 32, 16] : state === 'thinking' ? [8, 24, 8] : [16, 48, 24, 40, 16]
          }}
          transition={{
            repeat: Infinity,
            duration: state === 'speaking' ? 0.4 + i * 0.1 : 1.2,
            ease: "easeInOut",
            delay: i * 0.15
          }}
        />
      ))}
      <span className="ml-4 text-sm font-semibold tracking-widest uppercase opacity-70">
        {state}
      </span>
    </div>
  )
}
