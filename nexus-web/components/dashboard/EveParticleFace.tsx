"use client"

import { useEffect, useRef, useCallback } from "react"

interface Particle {
  x: number
  y: number
  baseX: number
  baseY: number
  vx: number
  vy: number
  size: number
  opacity: number
  hue: number
  isCore: boolean
}

interface Props {
  speaking: boolean
  loading?: boolean
  size?: number
  color?: string
}

// Female face landmark points — normalized 0-1 coordinates
// These define the face shape: oval outline, eyes, nose bridge, lips
function getFaceLandmarks(cx: number, cy: number, r: number): [number, number][] {
  const pts: [number, number][] = []

  // Face oval
  for (let i = 0; i < 60; i++) {
    const angle = (i / 60) * Math.PI * 2
    const rx = r * 0.52
    const ry = r * 0.68
    pts.push([cx + Math.cos(angle) * rx, cy + Math.sin(angle) * ry * (angle > 0 && angle < Math.PI ? 1.05 : 0.95)])
  }

  // Left eye — almond shape
  for (let i = 0; i < 20; i++) {
    const t = (i / 20) * Math.PI * 2
    const ex = cx - r * 0.22
    const ey = cy - r * 0.1
    pts.push([ex + Math.cos(t) * r * 0.14, ey + Math.sin(t) * r * 0.065])
  }
  // Left pupil
  for (let i = 0; i < 8; i++) {
    const t = (i / 8) * Math.PI * 2
    const ex = cx - r * 0.22
    const ey = cy - r * 0.1
    pts.push([ex + Math.cos(t) * r * 0.05, ey + Math.sin(t) * r * 0.05])
  }

  // Right eye
  for (let i = 0; i < 20; i++) {
    const t = (i / 20) * Math.PI * 2
    const ex = cx + r * 0.22
    const ey = cy - r * 0.1
    pts.push([ex + Math.cos(t) * r * 0.14, ey + Math.sin(t) * r * 0.065])
  }
  // Right pupil
  for (let i = 0; i < 8; i++) {
    const t = (i / 8) * Math.PI * 2
    const ex = cx + r * 0.22
    const ey = cy - r * 0.1
    pts.push([ex + Math.cos(t) * r * 0.05, ey + Math.sin(t) * r * 0.05])
  }

  // Nose bridge
  for (let i = 0; i < 12; i++) {
    const t = i / 11
    pts.push([cx + (Math.random() - 0.5) * r * 0.06, cy - r * 0.02 + t * r * 0.22])
  }
  // Nose tip
  for (let i = 0; i < 10; i++) {
    const t = (i / 10) * Math.PI
    pts.push([cx + Math.cos(t) * r * 0.1, cy + r * 0.2 + Math.sin(t) * r * 0.06])
  }

  // Lips — upper
  for (let i = 0; i < 24; i++) {
    const t = (i / 23) * Math.PI
    const lipY = cy + r * 0.35
    const lipCurveUpper = Math.sin(t) * r * 0.07
    pts.push([cx - r * 0.18 + (i / 23) * r * 0.36, lipY - lipCurveUpper])
  }
  // Lips — lower
  for (let i = 0; i < 20; i++) {
    const t = (i / 19) * Math.PI
    pts.push([cx - r * 0.16 + (i / 19) * r * 0.32, cy + r * 0.35 + Math.sin(t) * r * 0.09])
  }

  // Left eyebrow
  for (let i = 0; i < 14; i++) {
    const t = i / 13
    pts.push([cx - r * 0.32 + t * r * 0.22, cy - r * 0.22 - Math.sin(t * Math.PI) * r * 0.04])
  }
  // Right eyebrow
  for (let i = 0; i < 14; i++) {
    const t = i / 13
    pts.push([cx + r * 0.10 + t * r * 0.22, cy - r * 0.22 - Math.sin(t * Math.PI) * r * 0.04])
  }

  // Cheekbones — soft glow clusters
  for (let i = 0; i < 16; i++) {
    const angle = (Math.random() * Math.PI * 0.5) - Math.PI * 0.25
    pts.push([cx - r * 0.38 + Math.cos(angle) * r * 0.08, cy + r * 0.08 + Math.sin(angle) * r * 0.06])
    pts.push([cx + r * 0.38 + Math.cos(angle) * r * 0.08, cy + r * 0.08 + Math.sin(angle) * r * 0.06])
  }

  return pts
}

export default function EveParticleFace({ speaking, loading = false, size = 280, color = "#00c8ff" }: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const particlesRef = useRef<Particle[]>([])
  const animFrameRef = useRef<number>(0)
  const timeRef = useRef(0)
  const speakingRef = useRef(speaking)
  const loadingRef = useRef(loading)

  speakingRef.current = speaking
  loadingRef.current = loading

  const initParticles = useCallback(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    const cx = size / 2
    const cy = size / 2
    const r = size * 0.42

    const landmarks = getFaceLandmarks(cx, cy, r)
    const particles: Particle[] = []

    // Core face particles anchored to landmarks
    for (const [bx, by] of landmarks) {
      particles.push({
        x: bx + (Math.random() - 0.5) * 8,
        y: by + (Math.random() - 0.5) * 8,
        baseX: bx,
        baseY: by,
        vx: 0, vy: 0,
        size: 1.0 + Math.random() * 1.4,
        opacity: 0.5 + Math.random() * 0.5,
        hue: 185 + Math.random() * 30,
        isCore: true,
      })
    }

    // Ambient floating particles — give depth
    for (let i = 0; i < 80; i++) {
      const angle = Math.random() * Math.PI * 2
      const dist = (0.3 + Math.random() * 0.55) * r
      const bx = cx + Math.cos(angle) * dist
      const by = cy + Math.sin(angle) * dist * 0.9
      particles.push({
        x: bx, y: by,
        baseX: bx, baseY: by,
        vx: (Math.random() - 0.5) * 0.3,
        vy: (Math.random() - 0.5) * 0.3,
        size: 0.6 + Math.random() * 1.2,
        opacity: 0.15 + Math.random() * 0.25,
        hue: 185 + Math.random() * 40,
        isCore: false,
      })
    }

    particlesRef.current = particles
  }, [size])

  useEffect(() => {
    initParticles()
  }, [initParticles])

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    const ctx = canvas.getContext("2d")
    if (!ctx) return

    const dpr = window.devicePixelRatio || 1
    canvas.width = size * dpr
    canvas.height = size * dpr
    canvas.style.width = `${size}px`
    canvas.style.height = `${size}px`
    ctx.scale(dpr, dpr)

    function draw() {
      if (!ctx || !canvas) return
      timeRef.current += 0.016
      const t = timeRef.current
      const isSpeaking = speakingRef.current
      const isLoading = loadingRef.current

      ctx.clearRect(0, 0, size, size)

      // Ambient glow behind face
      const glowRadius = size * 0.38 + (isSpeaking ? Math.sin(t * 6) * 12 : 0)
      const grd = ctx.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, glowRadius)
      grd.addColorStop(0, "rgba(0,200,255,0.06)")
      grd.addColorStop(0.5, "rgba(0,200,255,0.03)")
      grd.addColorStop(1, "transparent")
      ctx.fillStyle = grd
      ctx.fillRect(0, 0, size, size)

      for (const p of particlesRef.current) {
        // Speaking: particles pulse outward with sine wave
        // Loading: slow drift
        // Idle: gentle breathing
        let targetX = p.baseX
        let targetY = p.baseY

        if (p.isCore) {
          if (isSpeaking) {
            const dist = Math.hypot(p.baseX - size / 2, p.baseY - size / 2)
            const pulse = Math.sin(t * 8 + dist * 0.05) * 4 * (dist / (size * 0.4))
            const angle = Math.atan2(p.baseY - size / 2, p.baseX - size / 2)
            targetX = p.baseX + Math.cos(angle) * pulse
            targetY = p.baseY + Math.sin(angle) * pulse
          } else if (isLoading) {
            targetX = p.baseX + Math.sin(t * 2 + p.baseX * 0.05) * 2
            targetY = p.baseY + Math.cos(t * 2 + p.baseY * 0.05) * 2
          } else {
            // Idle breathing
            targetX = p.baseX + Math.sin(t * 0.8 + p.baseX * 0.02) * 1.2
            targetY = p.baseY + Math.cos(t * 0.8 + p.baseY * 0.02) * 1.2
          }
          p.x += (targetX - p.x) * 0.12
          p.y += (targetY - p.y) * 0.12
        } else {
          // Ambient: float freely
          p.x += p.vx + Math.sin(t * 0.5 + p.baseX) * 0.15
          p.y += p.vy + Math.cos(t * 0.5 + p.baseY) * 0.15
          // Soft boundary — drift back toward base
          p.x += (p.baseX - p.x) * 0.003
          p.y += (p.baseY - p.y) * 0.003
        }

        // Opacity pulse on speaking
        const opacityMod = isSpeaking
          ? 0.7 + Math.sin(t * 10 + p.baseX * 0.1) * 0.3
          : 1.0

        const s = p.size * (isSpeaking ? 1 + Math.sin(t * 8) * 0.25 : 1)

        // Draw bubble — soft glow with inner core
        ctx.beginPath()
        ctx.arc(p.x, p.y, s, 0, Math.PI * 2)

        const grad = ctx.createRadialGradient(p.x - s * 0.3, p.y - s * 0.3, 0, p.x, p.y, s)
        grad.addColorStop(0, `hsla(${p.hue}, 90%, 85%, ${p.opacity * opacityMod})`)
        grad.addColorStop(0.5, `hsla(${p.hue}, 80%, 65%, ${p.opacity * opacityMod * 0.7})`)
        grad.addColorStop(1, `hsla(${p.hue}, 70%, 50%, 0)`)
        ctx.fillStyle = grad
        ctx.fill()
      }

      animFrameRef.current = requestAnimationFrame(draw)
    }

    animFrameRef.current = requestAnimationFrame(draw)
    return () => cancelAnimationFrame(animFrameRef.current)
  }, [size])

  return (
    <canvas
      ref={canvasRef}
      style={{ width: size, height: size }}
      className="block"
      aria-label="Eve particle face"
    />
  )
}
