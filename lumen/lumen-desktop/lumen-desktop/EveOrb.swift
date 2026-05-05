import SwiftUI

// MARK: - Eve Orb — JARVIS-style particle command interface

struct EveOrb: View {
    let status: EveStatus
    let audioLevel: Float

    private var col: Color { status.color }
    private var aud: CGFloat { CGFloat(audioLevel) }

    var body: some View {
        let isSpeaking  = status == .speaking
        let isListening = status == .listening
        let isThinking  = status == .thinking
        let speedMult: Double = isThinking ? 3.8 : (isSpeaking ? 2.2 : 1.0)

        ZStack {
            glowLayers(isSpeaking: isSpeaking)

            TimelineView(.animation) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    let c = CGPoint(x: size.width / 2, y: size.height / 2)
                    drawAudioWaves (ctx, c, t, isSpeaking, isListening, isThinking)  // Perplexity-style ripples
                    drawReticle    (ctx, c, t)
                    drawParticles  (ctx, c, t, speedMult)
                    drawArcs       (ctx, c, t, speedMult)
                    drawDataRing   (ctx, c, t, isListening)
                    drawInnerRing  (ctx, c, isSpeaking)
                    drawCoreGeom   (ctx, c)
                }
                .frame(width: 240, height: 240)
            }
        }
        .frame(width: 240, height: 240)
        .animation(.easeInOut(duration: 0.5), value: status)
    }

    // MARK: - Canvas: state-driven wave rings
    //
    // Per-state behavior (so Director sees AT A GLANCE which state Eve is in):
    //   .idle        — no rings (clean)
    //   .listening   — 4 expanding rings, modulated by mic audioLevel, listen color
    //   .thinking    — single big "heartbeat" ring breathing 1Hz (synthetic),
    //                  no audio modulation, think color. Distinct from speaking.
    //   .speaking    — 4 expanding rings + audio-reactive inner pulse, modulated
    //                  by TTS amplitude. Color lerps toward white at peak.
    private func drawAudioWaves(_ ctx: GraphicsContext, _ c: CGPoint, _ t: Double,
                                  _ isSpeaking: Bool, _ isListening: Bool, _ isThinking: Bool) {
        // Idle: skip wave rings entirely. Reticle + particles + arcs still
        // animate so the orb isn't completely dead — just calm.
        if !isSpeaking && !isListening && !isThinking { return }

        // Thinking: ONE heartbeat ring breathing in/out at the 1Hz cadence
        // the LumenStore heartbeat timer is already driving via audioLevel.
        // No expansion — the ring just inflates and deflates, like a held
        // breath. Visually distinct from speaking's outward ripples.
        if isThinking && !isSpeaking {
            let baseR: CGFloat = 56
            let breathe: CGFloat = baseR + aud * 28        // aud is 0.20…0.75 from heartbeat
            let alpha: Double = 0.30 + Double(aud) * 0.45
            ctx.stroke(
                Circle().path(in: CGRect(x: c.x - breathe, y: c.y - breathe,
                                          width: breathe * 2, height: breathe * 2)),
                with: .color(col.opacity(alpha)),
                style: StrokeStyle(lineWidth: 2.0)
            )
            // Subtle inner echo so the "breathing" reads even at low aud
            let inner: CGFloat = breathe * 0.55
            ctx.stroke(
                Circle().path(in: CGRect(x: c.x - inner, y: c.y - inner,
                                          width: inner * 2, height: inner * 2)),
                with: .color(col.opacity(alpha * 0.5)),
                style: StrokeStyle(lineWidth: 1.0)
            )
            return
        }

        // Listening / Speaking: four concurrent expanding rings (sonar pattern).
        let count: Int = 4
        let speed: Double = isSpeaking ? 1.4 : 0.9
        let baseAmp: Double = isSpeaking ? 0.55 : 0.42
        let audioBoost: Double = Double(aud) * (isSpeaking ? 0.55 : 0.35)
        let amplitude = baseAmp + audioBoost

        let maxRadius: CGFloat = 116 + CGFloat(audioBoost) * 18
        let minRadius: CGFloat = 8
        let cycle: Double = 2.6 / max(speed, 0.1)

        // Speaking: lerp color toward white as amplitude rises. Peak speech →
        // bright white-eve. Quiet → solid eve. Mirrors IRIS-AI's lerpColors.
        let highlightAmt: Double = isSpeaking ? min(1.0, Double(aud) * 1.4) : 0
        let drawColor: Color = isSpeaking
            ? Color(.sRGB, red: 0.4 + 0.6 * highlightAmt + 0.0,
                          green: 0.5 + 0.5 * highlightAmt,
                          blue: 0.95, opacity: 1.0)
            : col

        for i in 0..<count {
            let phase = (t / cycle + Double(i) / Double(count)).truncatingRemainder(dividingBy: 1.0)
            let radius = minRadius + (maxRadius - minRadius) * CGFloat(phase)
            let envelope = sin(phase * .pi)
            let alpha = amplitude * envelope
            ctx.stroke(
                Circle().path(in: CGRect(x: c.x - radius, y: c.y - radius,
                                          width: radius * 2, height: radius * 2)),
                with: .color(drawColor.opacity(alpha)),
                style: StrokeStyle(lineWidth: 1.6)
            )
        }

        // Speaking only: snap pulse — small bright ring tracks each audio
        // peak. Without TTS amplitude this stays at base radius; with it,
        // it visibly inflates on each loud syllable.
        if isSpeaking {
            let r: CGFloat = 18 + aud * 36
            ctx.stroke(
                Circle().path(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                with: .color(drawColor.opacity(0.55 + Double(aud) * 0.4)),
                style: StrokeStyle(lineWidth: 1.6)
            )
        }
    }

    // MARK: - SwiftUI glow layers (blur requires native views)

    @ViewBuilder
    private func glowLayers(isSpeaking: Bool) -> some View {
        // Outer ambient haze
        Circle()
            .fill(col.opacity(status == .idle ? 0.05 : 0.12))
            .frame(width: 230, height: 230)
            .blur(radius: 32)

        // Audio bloom (speaking only)
        if isSpeaking {
            Circle()
                .fill(col.opacity(0.12 + aud * 0.22))
                .frame(width: 120 + aud * 60, height: 120 + aud * 60)
                .blur(radius: 24)
                .animation(.easeOut(duration: 0.06), value: aud)
        }

        // Core bloom — 3 stacked circles with increasing blur
        let coreD: CGFloat = isSpeaking ? 22 + aud * 16 : 14
        Circle().fill(col.opacity(0.95)).frame(width: coreD, height: coreD).blur(radius: 10)
        Circle().fill(col.opacity(0.55)).frame(width: coreD, height: coreD).blur(radius: 20)
        Circle().fill(col.opacity(0.22)).frame(width: coreD, height: coreD).blur(radius: 38)
    }

    // MARK: - Canvas: outer reticle ring

    private func drawReticle(_ ctx: GraphicsContext, _ c: CGPoint, _ t: Double) {
        let r: CGFloat = 109
        let rot = t * 0.022  // slow CW drift

        // 48 tick marks at varying lengths
        for i in 0..<48 {
            let angle = Double(i) * .pi * 2 / 48 + rot
            let isCardinal = i % 12 == 0
            let isMajor    = i % 4  == 0
            let len: CGFloat = isCardinal ? 12 : (isMajor ? 6 : 3)
            let opacity     = isCardinal ? 0.65 : (isMajor ? 0.22 : 0.09)
            let lw: CGFloat = isCardinal ? 1.5 : 0.75

            let x1 = c.x + cos(angle) * r
            let y1 = c.y + sin(angle) * r
            let x2 = c.x + cos(angle) * (r - len)
            let y2 = c.y + sin(angle) * (r - len)
            ctx.stroke(Path { p in p.move(to: .init(x: x1, y: y1)); p.addLine(to: .init(x: x2, y: y2)) },
                       with: .color(col.opacity(opacity)), lineWidth: lw)
        }

        // Cardinal diamonds (N/E/S/W)
        for i in 0..<4 {
            let angle = Double(i) * .pi / 2 + rot
            let px = c.x + cos(angle) * (r + 9)
            let py = c.y + sin(angle) * (r + 9)
            let rad = CGPoint(x: cos(angle), y: sin(angle))
            let perp = CGPoint(x: -sin(angle), y:  cos(angle))
            let dl: CGFloat = 4.5
            let dw: CGFloat = 2.2
            var path = Path()
            path.move   (to: .init(x: px + rad.x * dl,  y: py + rad.y * dl))
            path.addLine(to: .init(x: px + perp.x * dw, y: py + perp.y * dw))
            path.addLine(to: .init(x: px - rad.x * dl,  y: py - rad.y * dl))
            path.addLine(to: .init(x: px - perp.x * dw, y: py - perp.y * dw))
            path.closeSubpath()
            ctx.fill(path, with: .color(col.opacity(0.80)))
        }

        // Ghost ring
        ctx.stroke(Circle().path(in: .init(x: c.x-r, y: c.y-r, width: r*2, height: r*2)),
                   with: .color(col.opacity(0.05)), lineWidth: 0.5)
    }

    // MARK: - Canvas: elliptical particle orbit (3-D depth illusion)

    private func drawParticles(_ ctx: GraphicsContext, _ c: CGPoint, _ t: Double, _ speedMult: Double) {
        let baseR: CGFloat = 83 + aud * 9
        let yScale: Double = 0.40   // compress vertical axis for depth

        // Faint orbit guide ellipse
        ctx.stroke(
            Ellipse().path(in: .init(x: c.x - baseR, y: c.y - baseR * yScale,
                                     width: baseR * 2, height: baseR * yScale * 2)),
            with: .color(col.opacity(0.06)), lineWidth: 0.5)

        let speed = 0.32 * speedMult
        for i in 0..<18 {
            let baseAngle = Double(i) * .pi * 2 / 18
            let angle = baseAngle + t * speed

            let px = c.x + cos(angle) * baseR
            let py = c.y + sin(angle) * baseR * yScale

            // Depth: sin(angle)==1 → near top (near), sin(angle)==-1 → bottom (far)
            let depth = (sin(angle) + 1) / 2          // 0 = far, 1 = near
            let sz: CGFloat = 1.3 + CGFloat(depth) * 2.2 + aud * 1.2
            let opacity = 0.20 + depth * 0.70

            ctx.fill(Circle().path(in: .init(x: px-sz/2, y: py-sz/2, width: sz, height: sz)),
                     with: .color(col.opacity(opacity)))

            // 2-dot comet tail
            for tail in 1...2 {
                let ta = angle - Double(tail) * 0.20
                let tx = c.x + cos(ta) * baseR
                let ty = c.y + sin(ta) * baseR * yScale
                let td = (sin(ta) + 1) / 2
                let tsz = max(0.6, sz - CGFloat(tail) * 0.85)
                ctx.fill(Circle().path(in: .init(x: tx-tsz/2, y: ty-tsz/2, width: tsz, height: tsz)),
                         with: .color(col.opacity(opacity * 0.35 / Double(tail) * (0.3 + td * 0.7))))
            }
        }
    }

    // MARK: - Canvas: targeting arc segments

    private func drawArcs(_ ctx: GraphicsContext, _ c: CGPoint, _ t: Double, _ speedMult: Double) {
        struct ArcCfg { let r: CGFloat; let span: Double; let spd: Double; let op: Double; let lw: CGFloat }
        let cfgs: [ArcCfg] = [
            .init(r: 65, span: .pi*0.48, spd:  0.48, op: 0.72, lw: 1.5),
            .init(r: 57, span: .pi*0.24, spd: -0.72, op: 0.48, lw: 1.2),
            .init(r: 49, span: .pi*0.14, spd:  1.05, op: 0.30, lw: 1.0),
            .init(r: 41, span: .pi*0.32, spd: -1.40, op: 0.22, lw: 0.8),
        ]
        for (i, cfg) in cfgs.enumerated() {
            let offset = Double(i) * .pi * 2 / 4
            let start  = t * cfg.spd * speedMult + offset
            ctx.stroke(
                Path { p in
                    p.addArc(center: c, radius: cfg.r,
                             startAngle: .radians(start), endAngle: .radians(start + cfg.span),
                             clockwise: false)
                },
                with: .color(col.opacity(cfg.op)),
                style: StrokeStyle(lineWidth: cfg.lw, lineCap: .round))
        }
    }

    // MARK: - Canvas: data dot ring (compressed ellipse = depth)

    private func drawDataRing(_ ctx: GraphicsContext, _ c: CGPoint, _ t: Double, _ isListening: Bool) {
        let r: CGFloat = 44
        let yScale = 0.48
        let rotSpd = isListening ? 0.09 : 0.024
        for i in 0..<24 {
            let angle = Double(i) * .pi * 2 / 24 + t * rotSpd
            let px = c.x + cos(angle) * r
            let py = c.y + sin(angle) * r * yScale
            let depth = (sin(angle) + 1) / 2
            let bright: Double = i % 6 == 0 ? 0.88 : (i % 2 == 0 ? 0.38 : 0.11)
            let sz: CGFloat = i % 6 == 0 ? 2.4 : 1.3
            ctx.fill(Circle().path(in: .init(x: px-sz/2, y: py-sz/2, width: sz, height: sz)),
                     with: .color(col.opacity(bright * (0.35 + depth * 0.65))))
        }
    }

    // MARK: - Canvas: audio-reactive inner ring

    private func drawInnerRing(_ ctx: GraphicsContext, _ c: CGPoint, _ isSpeaking: Bool) {
        let r1 = 22 + aud * (isSpeaking ? 22 : 10)
        let r2 = r1 * 0.68
        let op = 0.32 + aud * 0.52

        ctx.stroke(Circle().path(in: .init(x: c.x-r1, y: c.y-r1, width: r1*2, height: r1*2)),
                   with: .color(col.opacity(op)),
                   style: StrokeStyle(lineWidth: 1.5))
        ctx.stroke(Circle().path(in: .init(x: c.x-r2, y: c.y-r2, width: r2*2, height: r2*2)),
                   with: .color(col.opacity(op * 0.45)),
                   style: StrokeStyle(lineWidth: 0.75))
    }

    // MARK: - Canvas: central core dot

    private func drawCoreGeom(_ ctx: GraphicsContext, _ c: CGPoint) {
        let r: CGFloat = 4.5 + aud * 3.5
        ctx.fill(Circle().path(in: .init(x: c.x-r, y: c.y-r, width: r*2, height: r*2)),
                 with: .color(col.opacity(1.0)))
        // Small cross-hair lines through core
        let arm: CGFloat = 10
        ctx.stroke(Path { p in p.move(to: .init(x: c.x-arm, y: c.y)); p.addLine(to: .init(x: c.x+arm, y: c.y)) },
                   with: .color(col.opacity(0.25)), lineWidth: 0.5)
        ctx.stroke(Path { p in p.move(to: .init(x: c.x, y: c.y-arm)); p.addLine(to: .init(x: c.x, y: c.y+arm)) },
                   with: .color(col.opacity(0.25)), lineWidth: 0.5)
    }
}
