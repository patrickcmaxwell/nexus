import React, { useState, useRef, useEffect } from 'react'
import { motion, AnimatePresence } from 'framer-motion'

interface Props {
  onAuth: (sessionId: string) => void
}

export function PinAuth({ onAuth }: Props) {
  const [digits, setDigits]   = useState<string[]>(Array(4).fill(''))
  const [error, setError]     = useState('')
  const [loading, setLoading] = useState(false)
  const inputRefs             = useRef<(HTMLInputElement | null)[]>([])

  useEffect(() => { inputRefs.current[0]?.focus() }, [])

  function handleDigit(i: number, val: string) {
    if (!/^\d?$/.test(val)) return
    const next = [...digits]
    next[i] = val
    setDigits(next)
    setError('')
    if (val && i < 3) inputRefs.current[i + 1]?.focus()
    if (next.every(d => d) && i === 3) submit(next.join(''))
  }

  function handleKey(i: number, e: React.KeyboardEvent) {
    if (e.key === 'Backspace' && !digits[i] && i > 0) {
      inputRefs.current[i - 1]?.focus()
    }
    if (e.key === 'Enter' && digits.every(d => d)) submit(digits.join(''))
  }

  async function submit(pin: string) {
    setLoading(true)
    try {
      const res = await fetch('http://localhost:3000/api/security/pin', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Lumen-Client': '1' },
        body: JSON.stringify({ pin, remember: true }),
      })
      const data = await res.json()
      if (data.sessionId) {
        onAuth(data.sessionId)
      } else {
        setError('Invalid PIN')
        setDigits(Array(4).fill(''))
        inputRefs.current[0]?.focus()
      }
    } catch {
      setError('Cannot reach nexus-web — start it first')
    }
    setLoading(false)
  }

  return (
    <div className="h-screen w-screen bg-[#030303] flex flex-col items-center justify-center">
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        className="flex flex-col items-center gap-10"
      >
        {/* Logo mark */}
        <div className="flex flex-col items-center gap-3">
          <div className="w-14 h-14 rounded-full border border-white/10 flex items-center justify-center"
            style={{ boxShadow: '0 0 40px rgba(0,212,255,0.15)' }}>
            <span className="text-xs font-mono text-[#00d4ff]/70 tracking-widest">EVE</span>
          </div>
          <p className="text-[11px] font-mono tracking-[0.4em] text-white/20 uppercase">Nexus Desktop</p>
        </div>

        {/* PIN inputs */}
        <div className="flex gap-3">
          {digits.map((d, i) => (
            <input
              key={i}
              ref={el => { inputRefs.current[i] = el }}
              type="password"
              inputMode="numeric"
              maxLength={1}
              value={d}
              onChange={e => handleDigit(i, e.target.value)}
              onKeyDown={e => handleKey(i, e)}
              className="w-12 h-14 text-center text-xl font-mono bg-white/5 border border-white/10 rounded-xl text-white focus:outline-none focus:border-[#00d4ff]/50 focus:bg-white/8 transition-all caret-transparent"
              style={{ letterSpacing: d ? '0.1em' : undefined }}
            />
          ))}
        </div>

        <AnimatePresence>
          {error && (
            <motion.p
              initial={{ opacity: 0, y: -4 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0 }}
              className="text-xs font-mono text-red-400/80"
            >
              {error}
            </motion.p>
          )}
        </AnimatePresence>

        {loading && (
          <p className="text-[11px] font-mono text-white/20 tracking-widest animate-pulse">AUTHENTICATING...</p>
        )}
      </motion.div>
    </div>
  )
}
