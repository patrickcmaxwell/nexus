"use client"

import { useRef, useState, useCallback, useEffect, useMemo } from "react"
import {
  Map as MapIcon, RefreshCw, X, ExternalLink, ChevronRight, ChevronDown, Loader2,
  MessageSquare, Bot, Briefcase, Layers, FileText, Telescope, ShieldCheck,
  Pin, Archive, Activity, Users,
} from "lucide-react"
import Link from "next/link"

// ─── Types ────────────────────────────────────────────────────────────────────

type NodeType =
  | "conversation"
  | "agent"
  | "operation"
  | "topic"
  | "record"
  | "research"
  | "directive"
  | "human"

type RawNode = {
  id: string
  type: NodeType
  title: string
  subtitle: string
  preview: string
  tags: string[]
  status?: string | null
  priority?: string | null
  pinned?: boolean
  archived?: boolean
  messageCount: number
  createdAt: string
  updatedAt: string
  parentId?: string | null
  sourceConversationId?: string | null
  progressNote?: string | null
  findingsCount?: number | null
  model?: string | null
}

type Node3D = RawNode & {
  x: number; y: number; z: number
  sx: number; sy: number
  radius: number
  color: string
  accentColor: string
  vx: number; vy: number; vz: number
  pulseOffset: number
}

type Edge = { source: string; target: string; type: string }

// ─── Visual config per node type ──────────────────────────────────────────────

const TYPE_CONFIG: Record<NodeType, { color: string; accent: string; label: string }> = {
  conversation: { color: "#00d4ff", accent: "#004d5e", label: "Session"   },
  agent:        { color: "#a855f7", accent: "#3b0764", label: "Agent"     },
  operation:    { color: "#f59e0b", accent: "#451a03", label: "Op"        },
  topic:        { color: "#22c55e", accent: "#052e16", label: "Topic"     },
  record:       { color: "#fbbf24", accent: "#422006", label: "Record"    },
  research:     { color: "#06b6d4", accent: "#083344", label: "Research"  },
  directive:    { color: "#e11d48", accent: "#4c0519", label: "Directive" },
  human:        { color: "#f43f5e", accent: "#881337", label: "Human"     },
}

// Status-driven color overlays — tints the base type color based on live state.
// Values are hex strings we'll blend on top of the base; returning null means
// "no override, use type color."
function statusTint(type: NodeType, status?: string | null): string | null {
  if (!status) return null
  const s = status.toLowerCase()
  if (type === "operation") {
    if (s === "active")   return "#22c55e"  // green pulse
    if (s === "paused")   return "#60a5fa"  // blue
    if (s === "complete" || s === "completed") return "#6b7280" // muted
    if (s === "aborted" || s === "failed")     return "#ef4444" // red
  }
  if (type === "record") {
    if (s === "doing")    return "#06b6d4"
    if (s === "done")     return "#22c55e"
    if (s === "blocked")  return "#ef4444"
  }
  if (type === "research") {
    if (s === "running")  return "#06b6d4"
    if (s === "complete" || s === "completed") return "#22c55e"
    if (s === "failed" || s === "error")       return "#ef4444"
    if (s === "queued")   return "#94a3b8"
  }
  if (type === "agent") {
    if (s === "active" || s === "deployed") return "#22c55e"
    if (s === "offline" || s === "inactive") return "#6b7280"
  }
  if (type === "directive") {
    if (s === "inactive") return "#6b7280"
  }
  return null
}

// How fast should a node pulse? Higher = more attention-grabbing.
function pulseIntensity(type: NodeType, status?: string | null): number {
  const s = (status ?? "").toLowerCase()
  if (type === "research" && (s === "running")) return 2.2
  if (type === "research" && s === "failed")    return 1.6
  if (type === "operation" && s === "active")   return 1.5
  if (type === "record" && s === "doing")       return 1.2
  if (type === "record" && s === "blocked")     return 1.4
  if (type === "agent" && (s === "active" || s === "deployed")) return 1.1
  return 0.5
}

function timeAgo(d: string) {
  if (!d) return ""
  const m = Math.floor((Date.now() - new Date(d).getTime()) / 60000)
  if (m < 1) return "just now"
  if (m < 60) return `${m}m ago`
  const h = Math.floor(m / 60)
  if (h < 24) return `${h}h ago`
  return `${Math.floor(h / 24)}d ago`
}

// Cluster nodes by type so each type occupies a region of the sphere.
// Records orbit their parent operation, research jobs orbit their record,
// and child records orbit their parent record — so hierarchy is visible.
function buildNodes(raw: RawNode[]): Node3D[] {
  if (!raw.length) return []

  const byType: Record<NodeType, RawNode[]> = {
    conversation: [], agent: [], operation: [], topic: [],
    record: [], research: [], directive: [], human: [],
  }
  for (const n of raw) byType[n.type]?.push(n)

  // Each top-level cluster center (in 3D)
  const clusterCenters: Record<NodeType, [number, number, number]> = {
    conversation: [0,    0,    0  ],
    agent:        [220,  40,   80 ],
    operation:    [-200, -30,  100],
    topic:        [60,   -80, -180],
    directive:    [0,    160,  -40], // "above" the graph, like rules overseeing
    human:        [0,   -220,  0  ], // "below" the graph, like foundational actors
    record:       [-200, -30,  100], // laid out around their parent operation
    research:     [-200, -30,  100], // laid out around their parent record
  }

  const result: Node3D[] = []
  const byId = new Map<string, Node3D>()

  // Pass 1: lay out the "anchor" types (ones other nodes orbit around)
  const anchorTypes: NodeType[] = ["conversation", "agent", "operation", "topic", "directive", "human"]
  for (const type of anchorTypes) {
    const nodes = byType[type]
    const cfg = TYPE_CONFIG[type]
    const [cx, cy, cz] = clusterCenters[type]
    const spread = type === "conversation" ? 160 : type === "directive" ? 70 : 90

    nodes.forEach((n, i) => {
      // For conversations, we spread them out along a "time tunnel" (Z-axis)
      // to avoid a giant clump in the center. Newer = closer to viewer.
      let offsetZ = 0
      if (type === "conversation") {
        const date = new Date(n.createdAt).getTime()
        const now = Date.now()
        const ageDays = (now - date) / 86400000
        offsetZ = -ageDays * 2.5 // each day back is 2.5 units deeper
      }

      const phi   = Math.acos(-1 + (2 * i) / Math.max(nodes.length, 1))
      const theta = Math.sqrt(nodes.length * Math.PI) * phi
      const single = nodes.length === 1

      // Dynamic spread: grow the sphere as more nodes are added
      const spreadFactor = Math.sqrt(nodes.length / 50)
      const baseSpread = type === "conversation" ? 160 : type === "directive" ? 70 : 90
      const spread = baseSpread * Math.max(1, spreadFactor)

      // Base radius by type
      let radius =
        type === "conversation" ? 12 + Math.min(n.messageCount * 1.2, 16)
      : type === "agent"        ? 16
      : type === "operation"    ? 14
      : type === "directive"    ? 10
      : type === "human"        ? 18
      :                           12

      // If we have a massive amount of nodes, shrink them slightly to reduce noise
      if (nodes.length > 100) radius *= 0.85
      if (nodes.length > 250) radius *= 0.75

      // Size by priority / pinned / archived
      if (n.priority === "high" || n.priority === "critical") radius *= 1.25
      else if (n.priority === "low")                          radius *= 0.85
      if (n.pinned)                                           radius += 2
      if (n.archived)                                         radius *= 0.7

      const node: Node3D = {
        ...n,
        x: single ? cx : cx + spread * Math.cos(theta) * Math.sin(phi),
        y: single ? cy : cy + spread * 0.5 * Math.cos(phi),
        z: (single ? cz : cz + spread * Math.sin(theta) * Math.sin(phi)) + offsetZ,
        sx: 0, sy: 0,
        radius,
        color: cfg.color,
        accentColor: cfg.accent,
        vx: (Math.random() - 0.5) * 0.03,
        vy: (Math.random() - 0.5) * 0.02,
        vz: (Math.random() - 0.5) * 0.03,
        pulseOffset: Math.random() * Math.PI * 2,
      }
      result.push(node)
      byId.set(n.id, node)
    })
  }

  // Pass 2: lay out records — they orbit their parent (operation OR record)
  // Group records by parent so each operation gets an evenly-spaced record ring.
  const recordsByParent = new Map<string | null, RawNode[]>()
  for (const r of byType.record) {
    const p = r.parentId ?? null
    if (!recordsByParent.has(p)) recordsByParent.set(p, [])
    recordsByParent.get(p)!.push(r)
  }

  for (const [parentId, recs] of recordsByParent) {
    const parent = parentId ? byId.get(parentId) : null
    const cx = parent?.x ?? 0, cy = parent?.y ?? 0, cz = parent?.z ?? 0
    // Child records sit closer to their parent record; top-level records sit further from their op
    const parentType = parent?.type
    const orbit = parentType === "record" ? 35 : 50

    recs.forEach((r, i) => {
      const angle = (2 * Math.PI * i) / Math.max(recs.length, 1)
      // Slightly offset in 3D so records don't overlap visually
      const yOff = (i % 3 - 1) * 10

      let radius = 6
      if (r.priority === "high" || r.priority === "critical") radius = 8
      if (r.pinned)                                           radius += 1.5
      if (r.archived)                                         radius *= 0.7

      const node: Node3D = {
        ...r,
        x: cx + orbit * Math.cos(angle),
        y: cy + yOff,
        z: cz + orbit * Math.sin(angle),
        sx: 0, sy: 0,
        radius,
        color: TYPE_CONFIG.record.color,
        accentColor: TYPE_CONFIG.record.accent,
        vx: (Math.random() - 0.5) * 0.02,
        vy: (Math.random() - 0.5) * 0.012,
        vz: (Math.random() - 0.5) * 0.02,
        pulseOffset: Math.random() * Math.PI * 2,
      }
      result.push(node)
      byId.set(r.id, node)
    })
  }

  // Pass 3: research jobs orbit their record
  const researchByParent = new Map<string | null, RawNode[]>()
  for (const j of byType.research) {
    const p = j.parentId ?? null
    if (!researchByParent.has(p)) researchByParent.set(p, [])
    researchByParent.get(p)!.push(j)
  }

  for (const [parentId, jobs] of researchByParent) {
    const parent = parentId ? byId.get(parentId) : null
    const cx = parent?.x ?? 0, cy = parent?.y ?? 0, cz = parent?.z ?? 0
    const orbit = 22

    jobs.forEach((j, i) => {
      const angle = (2 * Math.PI * i) / Math.max(jobs.length, 1) + Math.PI / 4
      const radius = 7

      const node: Node3D = {
        ...j,
        x: cx + orbit * Math.cos(angle),
        y: cy - 8,
        z: cz + orbit * Math.sin(angle),
        sx: 0, sy: 0,
        radius,
        color: TYPE_CONFIG.research.color,
        accentColor: TYPE_CONFIG.research.accent,
        vx: (Math.random() - 0.5) * 0.015,
        vy: (Math.random() - 0.5) * 0.01,
        vz: (Math.random() - 0.5) * 0.015,
        pulseOffset: Math.random() * Math.PI * 2,
      }
      result.push(node)
      byId.set(j.id, node)
    })
  }

  return result
}

// ─── Canvas Drawing Helpers ───────────────────────────────────────────────────

function drawHexagon(ctx: CanvasRenderingContext2D, x: number, y: number, r: number) {
  ctx.beginPath()
  for (let i = 0; i < 6; i++) {
    const a = (Math.PI / 3) * i - Math.PI / 6
    if (i === 0) ctx.moveTo(x + r * Math.cos(a), y + r * Math.sin(a))
    else ctx.lineTo(x + r * Math.cos(a), y + r * Math.sin(a))
  }
  ctx.closePath()
}

function drawDiamond(ctx: CanvasRenderingContext2D, x: number, y: number, r: number) {
  ctx.beginPath()
  ctx.moveTo(x, y - r)
  ctx.lineTo(x + r * 0.7, y)
  ctx.lineTo(x, y + r)
  ctx.lineTo(x - r * 0.7, y)
  ctx.closePath()
}

function drawRoundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  ctx.beginPath()
  ctx.moveTo(x + r, y)
  ctx.lineTo(x + w - r, y); ctx.quadraticCurveTo(x + w, y, x + w, y + r)
  ctx.lineTo(x + w, y + h - r); ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h)
  ctx.lineTo(x + r, y + h); ctx.quadraticCurveTo(x, y + h, x, y + h - r)
  ctx.lineTo(x, y + r); ctx.quadraticCurveTo(x, y, x + r, y)
  ctx.closePath()
}

function drawSquare(ctx: CanvasRenderingContext2D, x: number, y: number, r: number) {
  ctx.beginPath()
  ctx.rect(x - r, y - r, r * 2, r * 2)
  ctx.closePath()
}

function drawTriangle(ctx: CanvasRenderingContext2D, x: number, y: number, r: number) {
  ctx.beginPath()
  ctx.moveTo(x, y - r)
  ctx.lineTo(x + r * 0.9, y + r * 0.7)
  ctx.lineTo(x - r * 0.9, y + r * 0.7)
  ctx.closePath()
}

// Draw node shape based on type
function drawNodeShape(ctx: CanvasRenderingContext2D, type: NodeType, x: number, y: number, r: number) {
  if (type === "agent")        drawHexagon(ctx, x, y, r)
  else if (type === "operation") drawDiamond(ctx, x, y, r)
  else if (type === "record")    drawSquare(ctx, x, y, r * 0.9)
  else if (type === "directive") drawTriangle(ctx, x, y, r)
  else /* conversation, topic, research */ ctx.beginPath(), ctx.arc(x, y, r, 0, Math.PI * 2)
}

// Blend two hex colors by a ratio (0 = a, 1 = b) — used for status tints.
function blendHex(a: string, b: string, ratio: number): string {
  const pa = parseInt(a.slice(1), 16), pb = parseInt(b.slice(1), 16)
  const ar = (pa >> 16) & 0xff, ag = (pa >> 8) & 0xff, ab = pa & 0xff
  const br = (pb >> 16) & 0xff, bg = (pb >> 8) & 0xff, bb = pb & 0xff
  const r = Math.round(ar + (br - ar) * ratio)
  const g = Math.round(ag + (bg - ag) * ratio)
  const bl = Math.round(ab + (bb - ab) * ratio)
  return "#" + [r, g, bl].map(v => v.toString(16).padStart(2, "0")).join("")
}

// ─── Neural Canvas ────────────────────────────────────────────────────────────

function NeuralCanvas({ nodes, edges, selectedId, onSelect, onDoubleSelect, visibleTypes }: {
  nodes: Node3D[]
  edges: Edge[]
  selectedId: string | null
  onSelect: (n: Node3D | null) => void
  onDoubleSelect: (n: Node3D) => void
  visibleTypes: Set<NodeType>
}) {
  const visibleRef = useRef<Set<NodeType>>(visibleTypes)
  useEffect(() => { visibleRef.current = visibleTypes }, [visibleTypes])
  const canvasRef   = useRef<HTMLCanvasElement>(null)
  const nodesRef    = useRef<Node3D[]>(nodes)
  const edgesRef    = useRef<Edge[]>(edges)
  const rotRef      = useRef({ x: 0.15, y: 0, tx: 0.15, ty: 0 })
  const dragRef     = useRef({ dragging: false, lastX: 0, lastY: 0 })
  // Idle auto-rotation stops the first time the user interacts with the map
  // (drag, wheel/pinch zoom, click a node). Once it stops, it stays stopped —
  // the user drives all motion after that point.
  const interactedRef = useRef(false)
  const zoomRef     = useRef(0.85)
  const zoomTargRef = useRef(0.85)   // target zoom for smooth animation
  const focusRef    = useRef<{ tx: number; ty: number } | null>(null) // pan-to-node target
  const rafRef      = useRef<number>(0)
  const selRef      = useRef<string | null>(selectedId)
  const hovRef      = useRef<string | null>(null)
  const lastClickRef = useRef<{ id: string; time: number } | null>(null)

  useEffect(() => { nodesRef.current = nodes }, [nodes])
  useEffect(() => { edgesRef.current = edges }, [edges])
  useEffect(() => { selRef.current = selectedId }, [selectedId])

  function project(x: number, y: number, z: number, cx: number, cy: number) {
    const rx = rotRef.current.x, ry = rotRef.current.y
    const x1 = x * Math.cos(ry) + z * Math.sin(ry)
    const z1 = -x * Math.sin(ry) + z * Math.cos(ry)
    const y1 = y * Math.cos(rx) - z1 * Math.sin(rx)
    const z2 = y * Math.sin(rx) + z1 * Math.cos(rx)
    const fov = 500
    // Prevent division by zero or negative scale for nodes behind the camera
    const denom = fov + z2
    if (denom < 1) return { sx: -9999, sy: -9999, sc: 0, z: z2 }
    const sc = (fov / denom) * zoomRef.current
    return { sx: cx + x1 * sc, sy: cy + y1 * sc, sc, z: z2 }
  }

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    const ctx = canvas.getContext("2d")!

    function resize() {
      const dpr = devicePixelRatio
      canvas.width = canvas.offsetWidth * dpr
      canvas.height = canvas.offsetHeight * dpr
      ctx.resetTransform()
      ctx.scale(dpr, dpr)
    }
    resize()
    const ro = new ResizeObserver(resize)
    ro.observe(canvas)

    // Static starfield
    const stars = Array.from({ length: 500 }, () => ({
      x: Math.random(), y: Math.random(),
      r: Math.random() * 1.0 + 0.2,
      a: Math.random() * 0.4 + 0.05,
      twinkle: Math.random() * Math.PI * 2,
    }))

    // Grid lines in background (subtle perspective grid)
    let t = 0

    function draw() {
      try {
        drawFrame()
      } catch (err) {
        // If the draw loop throws, surface it once — otherwise the animation
        // silently dies and the user sees a frozen canvas with no indication why.
        // eslint-disable-next-line no-console
        console.error("[v0] Nexus Map draw loop crashed:", err)
        return // stop the loop so we don't spam errors
      }
      rafRef.current = requestAnimationFrame(draw)
    }

    function drawFrame() {
      const W = canvas.offsetWidth, H = canvas.offsetHeight
      if (!W || !H) return
      t += 0.008

      // Smooth rotation
      rotRef.current.x += (rotRef.current.tx - rotRef.current.x) * 0.04
      rotRef.current.y += (rotRef.current.ty - rotRef.current.y) * 0.04
      // Idle spin only before the user has touched the map.
      if (!dragRef.current.dragging && !interactedRef.current) rotRef.current.ty += 0.0018

      // Smooth zoom animation toward target
      zoomRef.current += (zoomTargRef.current - zoomRef.current) * 0.06

      // Pan toward focused node if set
      if (focusRef.current) {
        rotRef.current.tx += (focusRef.current.tx - rotRef.current.tx) * 0.04
        rotRef.current.ty += (focusRef.current.ty - rotRef.current.ty) * 0.04
        const dTx = Math.abs(focusRef.current.tx - rotRef.current.tx)
        const dTy = Math.abs(focusRef.current.ty - rotRef.current.ty)
        if (dTx < 0.001 && dTy < 0.001) focusRef.current = null
      }

      const cx = W / 2, cy = H / 2

      // Background
      ctx.fillStyle = "#03050f"
      ctx.fillRect(0, 0, W, H)

      // Subtle vignette
      const vig = ctx.createRadialGradient(cx, cy, 0, cx, cy, Math.max(W, H) * 0.7)
      vig.addColorStop(0, "rgba(0,0,0,0)")
      vig.addColorStop(1, "rgba(0,0,0,0.55)")
      ctx.fillStyle = vig; ctx.fillRect(0, 0, W, H)

      // Starfield
      for (const s of stars) {
        const twinkleA = s.a * (0.7 + 0.3 * Math.sin(t * 1.2 + s.twinkle))
        ctx.beginPath()
        ctx.arc(s.x * W, s.y * H, s.r, 0, Math.PI * 2)
        ctx.fillStyle = `rgba(200,215,255,${twinkleA})`
        ctx.fill()
      }

      // Drift nodes (records/research drift less — they orbit their parent)
      for (const n of nodesRef.current) {
        n.x += n.vx; n.y += n.vy; n.z += n.vz
        if (Math.abs(n.x) > 350) n.vx *= -1
        if (Math.abs(n.y) > 200) n.vy *= -1
        if (Math.abs(n.z) > 350) n.vz *= -1
      }

      // Zoom-based level-of-detail. When zoomed out, hide the small stuff so
      // the graph stays legible. Records appear at zoom >= 1.3, research at
      // >= 1.6 — unless the viewer selected something nearby.
      const z = zoomRef.current
      const visible = visibleRef.current
      const sel = selRef.current

      // Compute a set of "nearby" ids: the selected node + its immediate children
      // so a selected operation reveals its records and a selected record reveals
      // its research regardless of zoom.
      const nearby = new Set<string>()
      if (sel) {
        nearby.add(sel)
        for (const e of edgesRef.current) {
          if (e.source === sel) nearby.add(e.target)
          if (e.target === sel) nearby.add(e.source)
        }
      }

      function isRendered(n: Node3D): boolean {
        if (!visible.has(n.type)) return false
        if (n.type === "record"   && z < 1.3 && !nearby.has(n.id)) return false
        if (n.type === "research" && z < 1.6 && !nearby.has(n.id)) return false
        return true
      }

      const projected = nodesRef.current
        .filter(isRendered)
        .map(n => {
          const p = project(n.x, n.y, n.z, cx, cy)
          n.sx = p.sx; n.sy = p.sy
          return { ...p, node: n }
        })

      // Which nodes are currently visible — used to skip edges with hidden endpoints.
      const visibleIds = new Set(projected.map(p => p.node.id))

      // ── Edges ──
      // Index projected nodes for fast lookup
      const byIdProj = new Map(projected.map(p => [p.node.id, p]))
      for (const e of edgesRef.current) {
        if (!visibleIds.has(e.source) || !visibleIds.has(e.target)) continue
        const a = byIdProj.get(e.source)
        const b = byIdProj.get(e.target)
        if (!a || !b) continue

        const isTopicLink    = e.type === "topic-link"
        const isRecordLink   = e.type === "record-belongs-to" || e.type === "record-parent"
        const isResearchOn   = e.type === "research-on"
        const isResearchMake = e.type === "research-producing"
        const isSourceLink   = e.type === "record-source"

        // Is this edge "live"? (touches something active)
        const liveStatus =
          a.node.status?.toLowerCase() === "running" ||
          b.node.status?.toLowerCase() === "running" ||
          a.node.status?.toLowerCase() === "active"  ||
          b.node.status?.toLowerCase() === "active"

        ctx.save()
        if (isTopicLink || isSourceLink) ctx.setLineDash([3, 5])
        else if (isResearchOn || isResearchMake) ctx.setLineDash([2, 3])
        else if (isRecordLink) ctx.setLineDash([4, 4])
        else ctx.setLineDash([6, 10])

        // Flow animation: marching ants on live edges
        if (liveStatus) ctx.lineDashOffset = -((t * 30) % 50)

        const midColor =
          isTopicLink    ? "#22c55e40"
        : isRecordLink   ? TYPE_CONFIG.record.color + "35"
        : isResearchOn   ? TYPE_CONFIG.research.color + (liveStatus ? "80" : "30")
        : isResearchMake ? TYPE_CONFIG.research.color + "40"
        : isSourceLink   ? TYPE_CONFIG.conversation.color + "25"
        :                  "#ffffff12"

        const g = ctx.createLinearGradient(a.sx, a.sy, b.sx, b.sy)
        g.addColorStop(0, a.node.color + "30")
        g.addColorStop(0.5, midColor)
        g.addColorStop(1, b.node.color + "30")

        ctx.beginPath()
        ctx.moveTo(a.sx, a.sy)
        const midX = (a.sx + b.sx) / 2
        const midY = (a.sy + b.sy) / 2 - 20
        ctx.quadraticCurveTo(midX, midY, b.sx, b.sy)
        ctx.strokeStyle = g
        ctx.lineWidth =
          liveStatus     ? 1.4
        : isTopicLink    ? 1.0
        : isRecordLink   ? 0.8
        : isResearchOn   ? 0.9
        : isResearchMake ? 0.7
        :                  0.6
        ctx.stroke()
        ctx.restore()
      }

      // ── Nexus core ──
      const cp = project(0, 0, 0, cx, cy)
      // Outer glow
      const cg = ctx.createRadialGradient(cp.sx, cp.sy, 0, cp.sx, cp.sy, 44)
      cg.addColorStop(0, "rgba(0,212,255,0.18)")
      cg.addColorStop(1, "rgba(0,212,255,0)")
      ctx.beginPath(); ctx.arc(cp.sx, cp.sy, 44, 0, Math.PI * 2)
      ctx.fillStyle = cg; ctx.fill()
      // Inner core ring
      ctx.beginPath(); ctx.arc(cp.sx, cp.sy, 8, 0, Math.PI * 2)
      ctx.strokeStyle = `rgba(0,212,255,${0.5 + Math.sin(t * 2.5) * 0.2})`
      ctx.lineWidth = 1.5; ctx.stroke()
      // Outer rings at different radii
      for (const [rad, opacity] of [[18, 0.15], [28, 0.08]] as [number, number][]) {
        ctx.beginPath(); ctx.arc(cp.sx, cp.sy, rad * cp.sc, 0, Math.PI * 2)
        ctx.strokeStyle = `rgba(0,212,255,${opacity})`
        ctx.lineWidth = 1; ctx.stroke()
      }
      // Rotating orbit ellipse
      ctx.beginPath()
      ctx.ellipse(cp.sx, cp.sy, 36 * cp.sc, 10 * cp.sc, t * 0.35, 0, Math.PI * 2)
      ctx.strokeStyle = "rgba(0,212,255,0.12)"; ctx.lineWidth = 0.8; ctx.stroke()
      // Nexus label
      ctx.font = "500 8px 'GeistMono',monospace"
      ctx.fillStyle = "rgba(0,212,255,0.35)"
      ctx.textAlign = "center"; ctx.textBaseline = "top"
      ctx.fillText("NEXUS", cp.sx, cp.sy + 12 * cp.sc)

      // ── Type cluster labels ──
      const clusterLabels: [NodeType, [number, number, number]][] = [
        ["agent",        [220, 40, 80]],
        ["operation",    [-200, -30, 100]],
        ["topic",        [60, -80, -180]],
        ["human",        [0, -220, 0]],
      ]
      for (const [type, pos] of clusterLabels) {
        const cp2 = project(pos[0], pos[1] + 70, pos[2], cx, cy)
        ctx.font = "600 9px 'GeistMono',monospace"
        ctx.fillStyle = TYPE_CONFIG[type].color + "40"
        ctx.textAlign = "center"; ctx.textBaseline = "middle"
        ctx.fillText(TYPE_CONFIG[type].label.toUpperCase() + " CLUSTER", cp2.sx, cp2.sy)
      }

      // ── Sort back-to-front ─��
      projected.sort((a, b) => a.z - b.z)

      const nowMs = Date.now()
      for (const { sx, sy, sc, node } of projected) {
        const r = node.radius * sc
        const isSel = node.id === selRef.current
        const isHov = node.id === hovRef.current

        // ── Status-driven color (blends the base type color toward a status tint)
        const tint = statusTint(node.type, node.status)
        const col = tint ? blendHex(node.color, tint, 0.55) : node.color

        // ── Pulse intensity from status
        const pIntensity = pulseIntensity(node.type, node.status)
        const pulse = 1 + Math.sin(t * 1.8 + node.pulseOffset) * 0.06 * pIntensity

        // ── Archived fade (entire node dims to ~25% alpha)
        const alphaMul = node.archived ? 0.25 : 1

        // ── Recent-activity glow (anything updated in the last 10 minutes gets a cyan halo)
        const ageMin = (nowMs - new Date(node.updatedAt).getTime()) / 60000
        const recentGlow = ageMin < 10 ? Math.max(0, 1 - ageMin / 10) : 0

        ctx.save()
        ctx.globalAlpha = alphaMul

        // ── Outer glow ──
        const glowR = Math.max(0, r * (isSel ? 3.2 : isHov ? 2.4 : 1.6) * pulse)
        if (glowR <= 0) continue // Skip rendering if radius is invalid
        const glow = ctx.createRadialGradient(sx, sy, 0, sx, sy, glowR)
        glow.addColorStop(0, col + (isSel ? "30" : isHov ? "20" : "10"))
        glow.addColorStop(1, col + "00")
        ctx.beginPath(); ctx.arc(sx, sy, glowR, 0, Math.PI * 2)
        ctx.fillStyle = glow; ctx.fill()

        // Recent activity ring (pulsing cyan corona on anything that just changed)
        if (recentGlow > 0.05) {
          ctx.beginPath(); ctx.arc(sx, sy, r * 2.2 + Math.sin(t * 3) * 2, 0, Math.PI * 2)
          ctx.strokeStyle = `rgba(0,212,255,${0.5 * recentGlow})`
          ctx.lineWidth = 1; ctx.stroke()
        }

        // ── Red alert pulse for failed/blocked
        const s = (node.status ?? "").toLowerCase()
        if (s === "failed" || s === "error" || s === "blocked" || s === "aborted") {
          const alert = 0.4 + Math.sin(t * 2.5) * 0.3
          ctx.beginPath(); ctx.arc(sx, sy, r * 2.6, 0, Math.PI * 2)
          ctx.strokeStyle = `rgba(239,68,68,${alert})`
          ctx.lineWidth = 1.2; ctx.stroke()
        }

        // ── Node body ──
        ctx.save()
        drawNodeShape(ctx, node.type, sx, sy, r * pulse)

        // Fill
        const bodyGrad = ctx.createRadialGradient(sx - r * 0.3, sy - r * 0.4, r * 0.05, sx, sy, r)
        bodyGrad.addColorStop(0, col + "cc")
        bodyGrad.addColorStop(0.6, col + "55")
        bodyGrad.addColorStop(1, col + "15")
        ctx.fillStyle = bodyGrad; ctx.fill()

        ctx.strokeStyle = col + (isSel ? "dd" : isHov ? "99" : "55")
        ctx.lineWidth = isSel ? 2 : 1
        ctx.stroke()
        ctx.restore()

        // ── Pinned marker (gold dot, top-right of the node)
        if (node.pinned) {
          ctx.beginPath()
          ctx.arc(sx + r * 0.7, sy - r * 0.7, Math.max(2, r * 0.2), 0, Math.PI * 2)
          ctx.fillStyle = "#fbbf24"; ctx.fill()
          ctx.strokeStyle = "rgba(3,5,15,0.8)"; ctx.lineWidth = 0.8; ctx.stroke()
        }

        // ── Research progress ring ──
        if (node.type === "research") {
          const jobStatus = (node.status ?? "").toLowerCase()
          const ringR = r * 1.5
          // Background ring
          ctx.beginPath(); ctx.arc(sx, sy, ringR, 0, Math.PI * 2)
          ctx.strokeStyle = TYPE_CONFIG.research.color + "22"; ctx.lineWidth = 1.5; ctx.stroke()

          if (jobStatus === "running") {
            // Sweeping arc — gives a sense of "working"
            const start = (t * 1.8) % (Math.PI * 2)
            const arcLen = Math.PI * 0.6
            ctx.beginPath(); ctx.arc(sx, sy, ringR, start, start + arcLen)
            ctx.strokeStyle = TYPE_CONFIG.research.color; ctx.lineWidth = 2; ctx.stroke()
          } else if (jobStatus === "queued") {
            // Dashed waiting ring
            ctx.save()
            ctx.setLineDash([4, 4])
            ctx.lineDashOffset = -((t * 12) % 20)
            ctx.beginPath(); ctx.arc(sx, sy, ringR, 0, Math.PI * 2)
            ctx.strokeStyle = "#94a3b8cc"; ctx.lineWidth = 1.3; ctx.stroke()
            ctx.restore()
          } else if (jobStatus === "complete" || jobStatus === "completed") {
            // Full solid ring, slightly muted
            ctx.beginPath(); ctx.arc(sx, sy, ringR, 0, Math.PI * 2)
            ctx.strokeStyle = "#22c55e99"; ctx.lineWidth = 1.8; ctx.stroke()
          } else if (jobStatus === "failed" || jobStatus === "error") {
            // Red ring (alert pulse already handled above)
            ctx.beginPath(); ctx.arc(sx, sy, ringR, 0, Math.PI * 2)
            ctx.strokeStyle = "#ef4444cc"; ctx.lineWidth = 1.8; ctx.stroke()
          }
        }

        // ── Selection rings ──
        if (isSel) {
          ctx.beginPath(); ctx.arc(sx, sy, r * 2.0, 0, Math.PI * 2)
          ctx.strokeStyle = col + "55"; ctx.lineWidth = 1; ctx.stroke()
          ctx.beginPath(); ctx.arc(sx, sy, r * 2.5, 0, Math.PI * 2)
          ctx.strokeStyle = col + "22"; ctx.lineWidth = 1; ctx.stroke()
          ctx.beginPath()
          ctx.ellipse(sx, sy, r * 2.8, r * 0.7, t * 0.8, 0, Math.PI * 2)
          ctx.strokeStyle = col + "44"; ctx.lineWidth = 0.8; ctx.stroke()
        }

        // ── Scan line effect for agents ──
        if (node.type === "agent") {
          const scanY = sy - r + ((t * 30 + node.pulseOffset * 10) % (r * 2))
          ctx.save()
          ctx.beginPath(); ctx.arc(sx, sy, r * pulse, 0, Math.PI * 2); ctx.clip()
          ctx.beginPath(); ctx.moveTo(sx - r, scanY); ctx.lineTo(sx + r, scanY)
          ctx.strokeStyle = col + "40"; ctx.lineWidth = 1; ctx.stroke()
          ctx.restore()
        }

        // ── Label ── (only for larger nodes or selected/hovered to reduce clutter)
        const showLabel = isSel || isHov || r >= 10
        if (showLabel) {
          const lbl = node.title.length > 18 ? node.title.slice(0, 16) + "…" : node.title
          const lfs = Math.max(8, Math.min(11, r * 0.55))
          ctx.font = `600 ${lfs}px 'Geist',sans-serif`
          ctx.fillStyle = isSel ? "rgba(255,255,255,0.95)" : isHov ? "rgba(255,255,255,0.8)" : col + "bb"
          ctx.textAlign = "center"; ctx.textBaseline = "top"
          ctx.fillText(lbl, sx, sy + r + 5)

          // Type badge (only on larger nodes; records/research too small otherwise)
          if (r >= 11) {
            const badge = TYPE_CONFIG[node.type].label
            ctx.font = `500 7px 'GeistMono',monospace`
            ctx.fillStyle = col + "55"
            ctx.fillText(badge.toUpperCase(), sx, sy + r + 5 + lfs + 3)
          }
        }

        // ── Hover tooltip ──
        if (isHov && !isSel) {
          const tw = 200
          const tx = Math.min(sx + r + 10, W - tw - 8)
          const ty = Math.max(sy - 50, 8)
          ctx.fillStyle = "rgba(3,5,15,0.97)"
          ctx.strokeStyle = col + "60"; ctx.lineWidth = 1
          drawRoundRect(ctx, tx, ty, tw, 72, 5); ctx.fill(); ctx.stroke()

          ctx.textAlign = "left"; ctx.textBaseline = "top"
          ctx.font = "500 8px 'GeistMono',monospace"; ctx.fillStyle = col
          const statusBit = node.status ? ` · ${String(node.status).toUpperCase()}` : ""
          ctx.fillText(`${TYPE_CONFIG[node.type].label.toUpperCase()}${statusBit} · ${timeAgo(node.updatedAt)}`, tx + 8, ty + 8)

          ctx.font = "600 11px 'Geist',sans-serif"; ctx.fillStyle = "rgba(255,255,255,0.9)"
          const hoverTitle = node.title.length > 22 ? node.title.slice(0, 20) + "…" : node.title
          ctx.fillText(hoverTitle, tx + 8, ty + 22)

          ctx.font = "400 9px 'Geist',sans-serif"; ctx.fillStyle = "rgba(255,255,255,0.45)"
          ctx.fillText(node.subtitle.slice(0, 32), tx + 8, ty + 38)

          // Research: show progress note; otherwise show tags
          if (node.type === "research" && node.progressNote) {
            ctx.font = "400 8px 'GeistMono',monospace"; ctx.fillStyle = TYPE_CONFIG.research.color + "99"
            ctx.fillText(node.progressNote.slice(0, 34), tx + 8, ty + 54)
          } else if (node.tags.length) {
            ctx.font = "400 8px 'GeistMono',monospace"; ctx.fillStyle = col + "70"
            ctx.fillText(node.tags.slice(0, 3).join(" · "), tx + 8, ty + 54)
          }
        }

        ctx.restore() // alphaMul
      }
    }

    rafRef.current = requestAnimationFrame(draw)
    return () => { cancelAnimationFrame(rafRef.current); ro.disconnect() }
  }, []) // only once — nodesRef/edgesRef stay current via useEffect above

  // Attach a non-passive native wheel listener so we can preventDefault() on
  // trackpad pinch (browsers fire wheel with ctrlKey=true) — otherwise the
  // whole page zooms alongside the map. React's synthetic onWheel is passive.
  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    const handler = (e: WheelEvent) => {
      const factor = e.ctrlKey ? 0.012 : 0.0012
      zoomTargRef.current = Math.max(0.25, Math.min(4.0, zoomTargRef.current - e.deltaY * factor))
      focusRef.current = null
      interactedRef.current = true
      e.preventDefault()
    }
    canvas.addEventListener("wheel", handler, { passive: false })
    return () => canvas.removeEventListener("wheel", handler)
  }, [])

  function hitTest(e: React.MouseEvent) {
    const rect = canvasRef.current!.getBoundingClientRect()
    const mx = e.clientX - rect.left, my = e.clientY - rect.top
    let best: Node3D | null = null, bestD = Infinity
    const visible = visibleRef.current
    for (const n of nodesRef.current) {
      if (!visible.has(n.type)) continue
      // sx/sy are set to 0 for nodes not projected this frame (LOD-hidden) — skip those too
      if (n.sx === 0 && n.sy === 0) continue
      const dx = n.sx - mx, dy = n.sy - my
      const dist = Math.sqrt(dx * dx + dy * dy)
      if (dist < Math.max(n.radius * 1.2, 16) && dist < bestD) { best = n; bestD = dist }
    }
    return best
  }

  function zoomToNode(n: Node3D) {
    // Compute rotation angles so the node faces front-center
    // We want to rotate so the node's position aligns with the camera's forward axis
    const targetZoom = Math.min(3.0, Math.max(1.4, 400 / (Math.sqrt(n.x * n.x + n.y * n.y + n.z * n.z) + 60)))
    zoomTargRef.current = targetZoom
    // Set rotation targets to face the node
    const ry = Math.atan2(n.x, n.z)
    const rx = -Math.atan2(n.y, Math.sqrt(n.x * n.x + n.z * n.z)) * 0.6
    focusRef.current = { tx: rx, ty: rotRef.current.ty + ry }
  }

  // Track pinch state for mobile zoom
  const pinchRef = useRef<{ dist: number; active: boolean }>({ dist: 0, active: false })

  function getTouchPos(t: React.Touch) {
    const rect = canvasRef.current!.getBoundingClientRect()
    return { x: t.clientX - rect.left, y: t.clientY - rect.top }
  }

  return (
    <canvas
      ref={canvasRef}
      className="w-full h-full block touch-none select-none"
      style={{ cursor: "grab" }}
      onClick={e => {
        if (dragRef.current.dragging) return
        const h = hitTest(e)
        if (!h) {
          onSelect(null)
          // Zoom out when clicking empty space
          zoomTargRef.current = Math.max(0.7, zoomTargRef.current * 0.85)
          return
        }
        const now = Date.now()
        const last = lastClickRef.current
        if (last && last.id === h.id && now - last.time < 400) {
          // Double-click — trigger expand
          onDoubleSelect(h)
          lastClickRef.current = null
        } else {
          // Single click — select and zoom to node
          lastClickRef.current = { id: h.id, time: now }
          onSelect(h.id !== selRef.current ? h : null)
          if (h.id !== selRef.current) zoomToNode(h)
        }
      }}
      onMouseDown={e => {
        dragRef.current = { dragging: false, lastX: e.clientX, lastY: e.clientY }
        interactedRef.current = true
      }}
      onMouseMove={e => {
        if (e.buttons === 1) {
          const dx = Math.abs(e.clientX - dragRef.current.lastX)
          const dy = Math.abs(e.clientY - dragRef.current.lastY)
          if (dx > 3 || dy > 3) { dragRef.current.dragging = true; focusRef.current = null }
          rotRef.current.ty += (e.clientX - dragRef.current.lastX) * 0.005
          rotRef.current.tx += (e.clientY - dragRef.current.lastY) * 0.005
          dragRef.current.lastX = e.clientX
          dragRef.current.lastY = e.clientY
        } else {
          const h = hitTest(e)
          hovRef.current = h?.id ?? null
          if (canvasRef.current) canvasRef.current.style.cursor = h ? "pointer" : "grab"
        }
      }}
      onMouseUp={() => { setTimeout(() => { dragRef.current.dragging = false }, 50) }}
      // Wheel is handled via non-passive native listener above so we can
      // preventDefault() on trackpad pinch (ctrlKey=true).
      onTouchStart={e => {
        interactedRef.current = true
        if (e.touches.length === 2) {
          // Start pinch zoom
          const a = e.touches[0], b = e.touches[1]
          const dx = a.clientX - b.clientX, dy = a.clientY - b.clientY
          pinchRef.current = { dist: Math.sqrt(dx * dx + dy * dy), active: true }
          dragRef.current.dragging = true
        } else if (e.touches.length === 1) {
          const t = e.touches[0]
          dragRef.current = { dragging: false, lastX: t.clientX, lastY: t.clientY }
          pinchRef.current.active = false
        }
      }}
      onTouchMove={e => {
        if (e.touches.length === 2 && pinchRef.current.active) {
          const a = e.touches[0], b = e.touches[1]
          const dx = a.clientX - b.clientX, dy = a.clientY - b.clientY
          const d = Math.sqrt(dx * dx + dy * dy)
          const ratio = d / pinchRef.current.dist
          zoomTargRef.current = Math.max(0.25, Math.min(4.0, zoomTargRef.current * ratio))
          pinchRef.current.dist = d
          focusRef.current = null
        } else if (e.touches.length === 1 && !pinchRef.current.active) {
          const t = e.touches[0]
          const dx = Math.abs(t.clientX - dragRef.current.lastX)
          const dy = Math.abs(t.clientY - dragRef.current.lastY)
          if (dx > 3 || dy > 3) { dragRef.current.dragging = true; focusRef.current = null }
          rotRef.current.ty += (t.clientX - dragRef.current.lastX) * 0.005
          rotRef.current.tx += (t.clientY - dragRef.current.lastY) * 0.005
          dragRef.current.lastX = t.clientX
          dragRef.current.lastY = t.clientY
        }
      }}
      onTouchEnd={e => {
        // Handle tap → select
        if (e.touches.length === 0 && !dragRef.current.dragging && !pinchRef.current.active) {
          const t = e.changedTouches[0]
          if (t) {
            const pos = getTouchPos(t)
            // Find node at tap location
            let best: Node3D | null = null, bestD = Infinity
            for (const n of nodesRef.current) {
              const ddx = n.sx - pos.x, ddy = n.sy - pos.y
              const dist = Math.sqrt(ddx * ddx + ddy * ddy)
              if (dist < Math.max(n.radius * 1.8, 28) && dist < bestD) { best = n; bestD = dist }
            }
            if (best) {
              const now = Date.now()
              const last = lastClickRef.current
              if (last && last.id === best.id && now - last.time < 400) {
                onDoubleSelect(best)
                lastClickRef.current = null
              } else {
                lastClickRef.current = { id: best.id, time: now }
                onSelect(best.id !== selRef.current ? best : null)
                if (best.id !== selRef.current) zoomToNode(best)
              }
            } else {
              onSelect(null)
            }
          }
        }
        if (e.touches.length === 0) {
          pinchRef.current.active = false
          setTimeout(() => { dragRef.current.dragging = false }, 50)
        }
      }}
    />
  )
}

// ─── Detail Panel ─────────────────────────────────────────────────────────────

function NodeDetailPanel({ node, onClose }: { node: Node3D; onClose: () => void }) {
  const [messages, setMessages] = useState<Array<{ id: string; role: string; content: string; created_at: string }>>([])
  const [loading, setLoading] = useState(false)
  const [expanded, setExpanded] = useState<string | null>(null)
  const cfg = TYPE_CONFIG[node.type]

  useEffect(() => {
    if (node.type !== "conversation") return
    setLoading(true)
    fetch(`/api/eve/history?conversationId=${node.id}`)
      .then(r => r.json())
      .then(d => setMessages(d.messages ?? []))
      .catch(() => setMessages([]))
      .finally(() => setLoading(false))
  }, [node.id, node.type])

  const typeIcon = {
    conversation: <MessageSquare size={12} />,
    agent:        <Bot size={12} />,
    operation:    <Briefcase size={12} />,
    topic:        <Layers size={12} />,
    record:       <FileText size={12} />,
    research:     <Telescope size={12} />,
    directive:    <ShieldCheck size={12} />,
    human:        <Users size={12} />,
  }[node.type]

  return (
    <div
      className="absolute top-0 right-0 bottom-0 flex flex-col z-20 w-full max-w-full sm:w-80 sm:max-w-[320px]"
      style={{
        background: "rgba(3,5,15,0.97)",
        borderLeft: `1px solid ${node.color}30`,
        backdropFilter: "blur(12px)",
      }}
    >
      {/* Header */}
      <div className="flex-none p-4" style={{ borderBottom: `1px solid ${node.color}18` }}>
        <div className="flex items-center justify-between mb-2">
          <div className="flex items-center gap-2">
            <span style={{ color: node.color }}>{typeIcon}</span>
            <span className="font-mono text-[9px] tracking-widest uppercase" style={{ color: node.color }}>
              {cfg.label}
            </span>
            {node.status && (
              <span
                className="font-mono text-[8px] tracking-widest uppercase px-1.5 py-0.5 rounded"
                style={{ background: node.color + "18", color: node.color }}
              >
                {node.status}
              </span>
            )}
            {node.pinned && (
              <span
                className="flex items-center gap-1 font-mono text-[8px] tracking-widest uppercase px-1.5 py-0.5 rounded"
                style={{ background: "#fbbf2420", color: "#fbbf24" }}
              >
                <Pin size={8} /> Pinned
              </span>
            )}
            {node.archived && (
              <span
                className="flex items-center gap-1 font-mono text-[8px] tracking-widest uppercase px-1.5 py-0.5 rounded"
                style={{ background: "rgba(255,255,255,0.06)", color: "rgba(255,255,255,0.4)" }}
              >
                <Archive size={8} /> Archived
              </span>
            )}
          </div>
          <button
            onClick={onClose}
            className="transition-colors p-1.5 -m-1.5 rounded"
            style={{ color: "rgba(255,255,255,0.5)" }}
            aria-label="Close"
          >
            <X size={16} />
          </button>
        </div>
        <p className="text-sm font-semibold leading-snug" style={{ color: "rgba(255,255,255,0.92)" }}>
          {node.title}
        </p>
        <p className="text-[11px] mt-1" style={{ color: "rgba(255,255,255,0.35)" }}>
          {node.subtitle} · {timeAgo(node.updatedAt)}
        </p>
        {node.tags.length > 0 && (
          <div className="flex flex-wrap gap-1 mt-2">
            {node.tags.slice(0, 5).map(tag => (
              <span
                key={tag}
                className="font-mono text-[8px] px-1.5 py-0.5 rounded"
                style={{ background: node.color + "15", color: node.color + "99", border: `1px solid ${node.color}25` }}
              >
                {tag}
              </span>
            ))}
          </div>
        )}
      </div>

      {/* Preview / description */}
      {node.preview && (
        <div className="flex-none px-4 py-3" style={{ borderBottom: `1px solid ${node.color}10` }}>
          <p className="text-[11px] leading-relaxed" style={{ color: "rgba(255,255,255,0.45)" }}>
            {node.preview.slice(0, 180)}{node.preview.length > 180 ? "…" : ""}
          </p>
        </div>
      )}

      {/* Actions */}
      <div className="flex-none px-4 py-3 flex gap-2" style={{ borderBottom: `1px solid ${node.color}10` }}>
        {node.type === "conversation" && (
          <>
            <Link
              href={`/dashboard/maxwell?c=${node.id}`}
              className="flex-1 flex items-center justify-center gap-1.5 py-1.5 text-[10px] font-medium rounded transition-colors"
              style={{ border: `1px solid ${node.color}40`, color: node.color }}
            >
              <ExternalLink size={9} /> Open Session
            </Link>
            <Link
              href={`/dashboard/maxwell?c=${node.id}&discuss=1`}
              className="flex-1 flex items-center justify-center gap-1.5 py-1.5 text-[10px] font-medium rounded transition-colors"
              style={{ border: "1px solid rgba(255,255,255,0.08)", color: "rgba(255,255,255,0.4)" }}
            >
              <ChevronRight size={9} /> Continue
            </Link>
          </>
        )}
        {node.type === "agent" && (
          <Link
            href="/dashboard/agents"
            className="flex-1 flex items-center justify-center gap-1.5 py-1.5 text-[10px] font-medium rounded transition-colors"
            style={{ border: `1px solid ${node.color}40`, color: node.color }}
          >
            <ExternalLink size={9} /> View Agents
          </Link>
        )}
        {node.type === "operation" && (
          <Link
            href="/dashboard/operations"
            className="flex-1 flex items-center justify-center gap-1.5 py-1.5 text-[10px] font-medium rounded transition-colors"
            style={{ border: `1px solid ${node.color}40`, color: node.color }}
          >
            <ExternalLink size={9} /> View Operations
          </Link>
        )}
        {node.type === "topic" && node.sourceConversationId && (
          <Link
            href={`/dashboard/maxwell?c=${node.sourceConversationId}`}
            className="flex-1 flex items-center justify-center gap-1.5 py-1.5 text-[10px] font-medium rounded transition-colors"
            style={{ border: `1px solid ${node.color}40`, color: node.color }}
          >
            <ExternalLink size={9} /> Source Session
          </Link>
        )}
        {node.type === "record" && (
          <>
            <Link
              href={`/dashboard/operations?record=${node.id.replace(/^rec-/, "")}`}
              className="flex-1 flex items-center justify-center gap-1.5 py-1.5 text-[10px] font-medium rounded transition-colors"
              style={{ border: `1px solid ${node.color}40`, color: node.color }}
            >
              <ExternalLink size={9} /> Open Record
            </Link>
            {node.sourceConversationId && (
              <Link
                href={`/dashboard/maxwell?c=${node.sourceConversationId}`}
                className="flex-1 flex items-center justify-center gap-1.5 py-1.5 text-[10px] font-medium rounded transition-colors"
                style={{ border: "1px solid rgba(255,255,255,0.08)", color: "rgba(255,255,255,0.4)" }}
              >
                <ChevronRight size={9} /> Source
              </Link>
            )}
          </>
        )}
        {node.type === "research" && node.parentId?.startsWith("rec-") && (
          <Link
            href={`/dashboard/operations?record=${node.parentId.slice(4)}`}
            className="flex-1 flex items-center justify-center gap-1.5 py-1.5 text-[10px] font-medium rounded transition-colors"
            style={{ border: `1px solid ${node.color}40`, color: node.color }}
          >
            <ExternalLink size={9} /> View Research
          </Link>
        )}
        {node.type === "research" && node.parentId?.startsWith("op-") && (
          <Link
            href="/dashboard/operations"
            className="flex-1 flex items-center justify-center gap-1.5 py-1.5 text-[10px] font-medium rounded transition-colors"
            style={{ border: `1px solid ${node.color}40`, color: node.color }}
          >
            <ExternalLink size={9} /> View Operation
          </Link>
        )}
        {node.type === "directive" && (
          <Link
            href="/dashboard/directives"
            className="flex-1 flex items-center justify-center gap-1.5 py-1.5 text-[10px] font-medium rounded transition-colors"
            style={{ border: `1px solid ${node.color}40`, color: node.color }}
          >
            <ExternalLink size={9} /> Manage Directives
          </Link>
        )}
      </div>

      {/* Research-specific status strip */}
      {node.type === "research" && (
        <div
          className="flex-none px-4 py-2.5 flex items-center gap-2 text-[10px] font-mono"
          style={{ borderBottom: `1px solid ${node.color}10`, background: "rgba(6,182,212,0.03)" }}
        >
          <Activity size={10} style={{ color: node.color }} />
          <span style={{ color: "rgba(255,255,255,0.5)" }}>
            {node.model ? `${node.model} · ` : ""}{node.status ?? "unknown"}
            {typeof node.findingsCount === "number" && node.status === "complete" ? ` · ${node.findingsCount} findings` : ""}
          </span>
        </div>
      )}

      {/* Conversation messages */}
      {node.type === "conversation" && (
        <div className="flex-1 overflow-y-auto px-4 py-3 flex flex-col gap-2">
          {loading ? (
            <div className="flex items-center justify-center py-10 gap-2" style={{ color: "rgba(255,255,255,0.2)" }}>
              <Loader2 size={13} className="animate-spin" />
              <span className="font-mono text-[9px] tracking-widest">Loading session...</span>
            </div>
          ) : messages.length === 0 ? (
            <p className="text-[10px] font-mono text-center py-10" style={{ color: "rgba(255,255,255,0.15)" }}>
              No messages
            </p>
          ) : messages.map(msg => {
            const isEve = msg.role === "assistant"
            const isExp = expanded === msg.id
            const long = msg.content.length > 160
            return (
              <div
                key={msg.id}
                className="rounded"
                style={{
                  background: isEve ? "rgba(0,212,255,0.04)" : "rgba(255,255,255,0.02)",
                  border: isEve ? "1px solid rgba(0,212,255,0.10)" : "1px solid rgba(255,255,255,0.05)",
                  padding: "7px 9px",
                }}
              >
                <div className="flex items-center justify-between mb-1">
                  <span
                    className="font-mono text-[8px] tracking-widest uppercase"
                    style={{ color: isEve ? "rgba(0,212,255,0.55)" : "rgba(255,255,255,0.2)" }}
                  >
                    {isEve ? "Eve" : "You"}
                  </span>
                  <span className="font-mono text-[8px]" style={{ color: "rgba(255,255,255,0.12)" }}>
                    {new Date(msg.created_at).toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit" })}
                  </span>
                </div>
                <p className="text-[10px] leading-relaxed" style={{ color: "rgba(255,255,255,0.55)" }}>
                  {isExp || !long ? msg.content : msg.content.slice(0, 160) + "…"}
                </p>
                {long && (
                  <button
                    onClick={() => setExpanded(isExp ? null : msg.id)}
                    className="mt-1 flex items-center gap-1 text-[8px] font-mono"
                    style={{ color: "rgba(255,255,255,0.2)" }}
                  >
                    <ChevronDown size={8} style={{ transform: isExp ? "rotate(180deg)" : "none", transition: "transform .2s" }} />
                    {isExp ? "Collapse" : "Expand"}
                  </button>
                )}
              </div>
            )
          })}
        </div>
      )}

      {/* For non-conversation nodes just show description */}
      {node.type !== "conversation" && node.preview && (
        <div className="flex-1 px-4 py-3">
          <p className="font-mono text-[9px] uppercase tracking-widest mb-2" style={{ color: node.color + "60" }}>
            Details
          </p>
          <p className="text-[11px] leading-relaxed" style={{ color: "rgba(255,255,255,0.5)" }}>
            {node.preview}
          </p>
        </div>
      )}
    </div>
  )
}

// ─── Legend ───────────────────────────────────────────────────────────────────

function MapLegend({ counts, visibleTypes, onToggle }: {
  counts: Record<NodeType, number>
  visibleTypes: Set<NodeType>
  onToggle: (t: NodeType) => void
}) {
  const items: [NodeType, string][] = [
    ["conversation", "Sessions"],
    ["agent",        "Agents"],
    ["operation",    "Operations"],
    ["record",       "Records"],
    ["research",     "Research"],
    ["directive",    "Directives"],
    ["topic",        "Topics"],
  ]
  return (
    <div
      className="absolute bottom-5 left-5 flex flex-col gap-1 z-10"
      style={{ background: "rgba(3,5,15,0.85)", border: "1px solid rgba(255,255,255,0.06)", borderRadius: 6, padding: "8px 10px" }}
    >
      {items.map(([type, label]) => {
        const count = counts[type] ?? 0
        const on = visibleTypes.has(type)
        return (
          <button
            key={type}
            onClick={() => onToggle(type)}
            className="flex items-center gap-2 transition-opacity hover:opacity-100"
            style={{ opacity: on ? 1 : 0.35 }}
          >
            <div
              className="w-2 h-2 rounded-full flex-none"
              style={{ background: on ? TYPE_CONFIG[type].color : "rgba(255,255,255,0.2)" }}
            />
            <span className="font-mono text-[9px] text-left" style={{ color: "rgba(255,255,255,0.55)", minWidth: 68 }}>
              {label}
            </span>
            <span className="font-mono text-[9px] ml-auto" style={{ color: on ? TYPE_CONFIG[type].color + "aa" : "rgba(255,255,255,0.25)" }}>
              {count}
            </span>
          </button>
        )
      })}
    </div>
  )
}

// ─── Page ─────────────────────────────────────────────────────────────────────

const ALL_TYPES: NodeType[] = ["conversation", "agent", "operation", "record", "research", "directive", "topic"]

export default function NexusMapPage() {
  const [rawNodes, setRawNodes] = useState<RawNode[]>([])
  const [nodes, setNodes] = useState<Node3D[]>([])
  const [edges, setEdges] = useState<Edge[]>([])
  const [selected, setSelected] = useState<Node3D | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [expandedIds, setExpandedIds] = useState<Set<string>>(new Set())
  const [activeResearch, setActiveResearch] = useState(0)
  const [visibleTypes, setVisibleTypes] = useState<Set<NodeType>>(new Set(ALL_TYPES))
  const [timeWindowDays, setTimeWindowDays] = useState<number | null>(null) // null = all time
  const [searchQuery, setSearchQuery] = useState("")

  // Apply search filtering
  const finalNodes = useMemo(() => {
    if (!searchQuery) return nodes
    const q = searchQuery.toLowerCase()
    return nodes.map(n => {
      const match = n.title.toLowerCase().includes(q) || n.subtitle.toLowerCase().includes(q)
      // Fade out non-matching nodes
      return match ? n : { ...n, archived: true }
    })
  }, [nodes, searchQuery])

  // Double-click: expand a node by adding its tags as orbiting sub-nodes
  const handleDoubleSelect = useCallback((node: Node3D) => {
    if (expandedIds.has(node.id)) {
      // Collapse — remove sub-nodes for this parent
      setExpandedIds(prev => { const s = new Set(prev); s.delete(node.id); return s })
      setNodes(prev => prev.filter(n => n.id !== `${node.id}-sub-${n.title}`))
      setEdges(prev => prev.filter(e => e.source !== node.id || e.type !== "sub-link"))
      return
    }
    if (!node.tags || node.tags.length === 0) return
    setExpandedIds(prev => new Set(prev).add(node.id))

    const subNodes: Node3D[] = node.tags.slice(0, 8).map((tag, i) => {
      const angle = (2 * Math.PI * i) / node.tags.length
      const r = 80
      return {
        id: `${node.id}-sub-${tag}`,
        type: "topic" as NodeType,
        title: tag,
        subtitle: `from ${node.title}`,
        preview: `Keyword from "${node.title}"`,
        tags: [],
        messageCount: 0,
        createdAt: node.createdAt,
        updatedAt: node.updatedAt,
        sourceConversationId: node.id,
        x: node.x + r * Math.cos(angle),
        y: node.y + r * 0.4 * Math.sin(angle * 1.3),
        z: node.z + r * Math.sin(angle),
        sx: 0, sy: 0,
        radius: 7,
        color: "#22c55e",
        accentColor: "#052e16",
        vx: (Math.random() - 0.5) * 0.015,
        vy: (Math.random() - 0.5) * 0.01,
        vz: (Math.random() - 0.5) * 0.015,
        pulseOffset: Math.random() * Math.PI * 2,
      }
    })

    const subEdges: Edge[] = subNodes.map(sn => ({
      source: node.id,
      target: sn.id,
      type: "sub-link",
    }))

    setNodes(prev => [...prev, ...subNodes])
    setEdges(prev => [...prev, ...subEdges])
  }, [expandedIds])

  const fetchData = useCallback(async (opts?: { silent?: boolean }) => {
    if (!opts?.silent) setLoading(true)
    setError(null)
    try {
      const res = await fetch("/api/nexus-map")
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const data = await res.json()
      setRawNodes(data.nodes ?? [])
      setEdges(data.edges ?? [])
      setActiveResearch(data.activeResearch ?? 0)
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Unknown error")
    } finally {
      if (!opts?.silent) setLoading(false)
    }
  }, [])

  useEffect(() => { fetchData() }, [fetchData])

  // Smart polling: poll every 10s when there's an active research job (so
  // progress rings and flow edges stay live), else poll every 60s. Pause
  // polling entirely when the tab is hidden to save battery.
  useEffect(() => {
    const interval = activeResearch > 0 ? 10_000 : 60_000
    let timer: ReturnType<typeof setInterval> | null = null

    const start = () => {
      if (timer) return
      timer = setInterval(() => fetchData({ silent: true }), interval)
    }
    const stop = () => { if (timer) { clearInterval(timer); timer = null } }

    const onVis = () => {
      if (document.visibilityState === "visible") start()
      else stop()
    }
    document.addEventListener("visibilitychange", onVis)
    if (document.visibilityState === "visible") start()

    return () => { stop(); document.removeEventListener("visibilitychange", onVis) }
  }, [activeResearch, fetchData])

  // Apply the time-window filter BEFORE laying out the graph, so orbits
  // don't have gaps for hidden records. Archived items stay in the graph
  // but the draw loop fades them to ~25% opacity.
  const filteredRawNodes = useMemo(() => {
    if (!timeWindowDays) return rawNodes
    const cutoff = Date.now() - timeWindowDays * 86400_000
    return rawNodes.filter(n => new Date(n.updatedAt).getTime() >= cutoff)
  }, [rawNodes, timeWindowDays])

  useEffect(() => { setNodes(buildNodes(filteredRawNodes)) }, [filteredRawNodes])

  const counts = rawNodes.reduce((acc, n) => {
    acc[n.type] = (acc[n.type] ?? 0) + 1
    return acc
  }, {} as Record<NodeType, number>)
  const totalCounts: Record<NodeType, number> = {
    conversation: counts.conversation ?? 0,
    agent:        counts.agent        ?? 0,
    operation:    counts.operation    ?? 0,
    topic:        counts.topic        ?? 0,
    record:       counts.record       ?? 0,
    research:     counts.research     ?? 0,
    directive:    counts.directive    ?? 0,
  }

  const toggleType = useCallback((t: NodeType) => {
    setVisibleTypes(prev => {
      const next = new Set(prev)
      if (next.has(t)) next.delete(t)
      else next.add(t)
      return next
    })
  }, [])

  return (
    <div className="flex flex-col h-[calc(100dvh-5rem)] md:h-screen" style={{ background: "#03050f" }}>
      {/* Header */}
      <div
        className="flex-none flex items-center gap-2 md:gap-3 px-3 md:px-5 py-2 md:py-2.5 z-10"
        style={{ borderBottom: "1px solid rgba(0,212,255,0.08)", background: "rgba(3,5,15,0.95)" }}
      >
        <MapIcon size={13} style={{ color: "rgba(0,212,255,0.7)" }} />
        <span className="font-semibold text-sm tracking-wide" style={{ color: "rgba(255,255,255,0.9)" }}>
          Nexus Map
        </span>
        <span className="hidden md:inline font-mono text-[9px] uppercase tracking-widest" style={{ color: "rgba(255,255,255,0.15)" }}>
          Intelligence Network
        </span>
        <div className="ml-auto flex items-center gap-2 md:gap-3">
          {/* Active research pill — visible only when jobs are running */}
          {activeResearch > 0 && (
            <div
              className="flex items-center gap-1.5 px-2 py-1 rounded font-mono text-[9px]"
              style={{
                background: "rgba(6,182,212,0.12)",
                border: "1px solid rgba(6,182,212,0.35)",
                color: "#06b6d4",
              }}
            >
              <Activity size={9} className="animate-pulse" />
              <span>{activeResearch} researching</span>
            </div>
          )}

          {/* Search box */}
          <div className="relative group">
            <div className="absolute inset-y-0 left-2.5 flex items-center pointer-events-none text-primary/40 group-focus-within:text-primary/70 transition-colors">
              <Telescope size={10} />
            </div>
            <input
              type="text"
              placeholder="Search map..."
              value={searchQuery}
              onChange={e => setSearchQuery(e.target.value)}
              className="w-32 md:w-48 font-mono text-[9px] pl-7 pr-7 py-1 rounded outline-none transition-all focus:ring-1 focus:ring-primary/30"
              style={{
                background: "rgba(3,5,15,0.7)",
                border: "1px solid rgba(255,255,255,0.08)",
                color: "rgba(255,255,255,0.8)",
              }}
            />
            {searchQuery && (
              <button
                onClick={() => setSearchQuery("")}
                className="absolute inset-y-0 right-2 flex items-center text-primary/40 hover:text-primary transition-colors"
              >
                <X size={10} />
              </button>
            )}
          </div>

          {/* Time window */}
          <select
            value={timeWindowDays ?? "all"}
            onChange={e => setTimeWindowDays(e.target.value === "all" ? null : Number(e.target.value))}
            className="hidden sm:block font-mono text-[9px] px-2 py-1 rounded"
            style={{
              background: "rgba(3,5,15,0.95)",
              border: "1px solid rgba(255,255,255,0.08)",
              color: "rgba(255,255,255,0.6)",
            }}
          >
            <option value="all">All time</option>
            <option value="7">Last 7d</option>
            <option value="30">Last 30d</option>
            <option value="90">Last 90d</option>
          </select>

          <button
            onClick={() => fetchData()}
            className="flex items-center gap-1.5 px-2.5 md:px-3 py-1.5 text-[10px] font-medium rounded transition-colors"
            style={{ border: "1px solid rgba(255,255,255,0.08)", color: "rgba(255,255,255,0.5)" }}
            title="Refresh"
          >
            <RefreshCw size={9} className={loading ? "animate-spin" : ""} />
            <span className="hidden sm:inline">Refresh</span>
          </button>
        </div>
      </div>

      {/* Canvas area */}
      <div className="flex-1 relative overflow-hidden">
        {error && (
          <div
            className="absolute top-4 left-1/2 -translate-x-1/2 px-4 py-2 text-xs font-mono z-30 rounded"
            style={{ background: "rgba(239,68,68,0.08)", border: "1px solid rgba(239,68,68,0.25)", color: "#f87171" }}
          >
            {error}
          </div>
        )}

        {loading && (
          <div className="absolute inset-0 flex items-center justify-center z-20 pointer-events-none">
            <div className="flex flex-col items-center gap-3">
              <div
                className="w-7 h-7 rounded-full animate-spin"
                style={{ border: "1.5px solid rgba(0,212,255,0.12)", borderTopColor: "rgba(0,212,255,0.7)" }}
              />
              <span className="font-mono text-[10px] tracking-widest" style={{ color: "rgba(255,255,255,0.2)" }}>
                Mapping intelligence network...
              </span>
            </div>
          </div>
        )}

        <NeuralCanvas
          nodes={finalNodes}
          edges={edges}
          selectedId={selected?.id ?? null}
          onSelect={setSelected}
          onDoubleSelect={handleDoubleSelect}
          visibleTypes={visibleTypes}
        />

        {!loading && nodes.length === 0 && !error && (
          <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
            <div className="text-center pointer-events-auto">
              <p className="text-sm font-medium mb-1.5" style={{ color: "rgba(255,255,255,0.7)" }}>
                Neural map is empty
              </p>
              <p className="text-xs mb-5" style={{ color: "rgba(255,255,255,0.2)" }}>
                Talk to Eve. Create agents and operations.<br />
                Ask Eve to &quot;add this to the map&quot; during any conversation.
              </p>
              <Link
                href="/dashboard/maxwell"
                className="text-xs font-medium px-4 py-2 rounded transition-colors"
                style={{ border: "1px solid rgba(0,212,255,0.3)", color: "rgba(0,212,255,0.8)" }}
              >
                Open Eve
              </Link>
            </div>
          </div>
        )}

        {!loading && nodes.length > 0 && !selected && (
          <MapLegend counts={totalCounts} visibleTypes={visibleTypes} onToggle={toggleType} />
        )}

        {!loading && nodes.length > 0 && !selected && (
          <p
            className="hidden md:block absolute bottom-5 right-5 font-mono text-[8px] tracking-widest pointer-events-none"
            style={{ color: "rgba(255,255,255,0.15)" }}
          >
            Drag · Pinch/scroll to zoom · Click to inspect · Zoom in to see records
          </p>
        )}
        {!loading && nodes.length > 0 && !selected && (
          <p
            className="md:hidden absolute bottom-3 left-1/2 -translate-x-1/2 font-mono text-[8px] tracking-widest pointer-events-none whitespace-nowrap"
            style={{ color: "rgba(255,255,255,0.2)" }}
          >
            Drag · Pinch · Tap
          </p>
        )}

        {selected && (
          <NodeDetailPanel node={selected} onClose={() => setSelected(null)} />
        )}
      </div>
    </div>
  )
}
