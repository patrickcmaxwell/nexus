// NexusMapView.swift
//
// 3D "universe" of all things inside Nexus — operations, agents, records,
// conversations, research jobs, directives, humans, topic nodes — laid out
// as a starfield. Clusters by entity type sit at fixed positions in space;
// inside each cluster, individual nodes are placed on a sphere. Edges from
// /api/nexus-map are drawn as luminous lines between related nodes.
//
// Built on SceneKit (native macOS 3D, no SDKs). SceneView's allowsCameraControl
// gives us free orbit/pan/zoom out of the box. Tap a node → store posts a
// notification → MainView opens the entity's detail window.

import SwiftUI
import SceneKit

enum NexusMapMode: String, CaseIterable, Identifiable {
    case twoD, threeD
    var id: String { rawValue }
    var label: String { self == .twoD ? "2D" : "3D" }
}

struct NexusMapView: View {
    @ObservedObject var store: LumenStore
    @State private var search: String = ""
    @State private var typeFilter: String = "all"
    @State private var selected: NexusMapNode?
    @State private var anchorId: String?    // node currently in focus mode — drives dimming + cycle list
    @State private var sceneRefreshKey = UUID()  // re-creates scene when filter/data changes
    @State private var mode: NexusMapMode = .twoD  // Director's pref — readable map, 3D as alt
    @AppStorage("lumen.map.mode") private var persistedMode: String = NexusMapMode.twoD.rawValue

    private let allTypes: [String] = ["all", "operation", "agent", "record", "conversation", "research", "directive", "topic", "human"]

    private var filteredNodes: [NexusMapNode] {
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        return store.nexusMap.nodes.filter { n in
            (typeFilter == "all" || n.type == typeFilter) &&
            (q.isEmpty || n.title.lowercased().contains(q) || n.preview.lowercased().contains(q) || n.tags.joined(separator: " ").lowercased().contains(q))
        }
    }

    private var typeCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for n in store.nexusMap.nodes { counts[n.type, default: 0] += 1 }
        return counts
    }

    /// Anchor node (focus target) + its 1-hop neighbors. Used to dim
    /// everything else on the map and to drive the prev/next cycle list.
    private var focusContext: (anchor: NexusMapNode, cycle: [NexusMapNode], focusIds: Set<String>)? {
        guard let aid = anchorId,
              let anchor = store.nexusMap.nodes.first(where: { $0.id == aid }) else { return nil }
        let nodesById = Dictionary(uniqueKeysWithValues: store.nexusMap.nodes.map { ($0.id, $0) })
        var neighborIds: [String] = []
        var seen = Set<String>([anchor.id])
        for e in store.nexusMap.edges {
            if e.source == anchor.id, !seen.contains(e.target) {
                seen.insert(e.target); neighborIds.append(e.target)
            } else if e.target == anchor.id, !seen.contains(e.source) {
                seen.insert(e.source); neighborIds.append(e.source)
            }
        }
        let neighbors = neighborIds.compactMap { nodesById[$0] }
        let cycle = [anchor] + neighbors
        return (anchor, cycle, Set(cycle.map(\.id)))
    }

    private var cycleIndex: Int {
        guard let ctx = focusContext else { return 0 }
        return ctx.cycle.firstIndex(where: { $0.id == selected?.id }) ?? 0
    }

    private func handleSelect(_ node: NexusMapNode) {
        // Tapping a node on the map sets it as the anchor (focus mode).
        anchorId = node.id
        selected = node
        NotificationCenter.default.post(
            name: .lumenMapNodeTap,
            object: nil,
            userInfo: ["type": node.type, "id": node.id]
        )
    }

    private func cyclePrev() {
        guard let ctx = focusContext, !ctx.cycle.isEmpty else { return }
        let i = (cycleIndex - 1 + ctx.cycle.count) % ctx.cycle.count
        withAnimation(.easeInOut(duration: 0.15)) { selected = ctx.cycle[i] }
    }

    private func cycleNext() {
        guard let ctx = focusContext, !ctx.cycle.isEmpty else { return }
        let i = (cycleIndex + 1) % ctx.cycle.count
        withAnimation(.easeInOut(duration: 0.15)) { selected = ctx.cycle[i] }
    }

    private func clearFocus() {
        withAnimation(.easeOut(duration: 0.18)) {
            selected = nil
            anchorId = nil
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if mode == .twoD {
                    NexusMap2DScene(
                        nodes: filteredNodes,
                        edges: store.nexusMap.edges,
                        selectedId: selected?.id,
                        anchorId: anchorId,
                        focusedIds: focusContext?.focusIds ?? [],
                        onSelectNode: handleSelect
                    )
                } else {
                    NexusMap3DScene(
                        nodes: filteredNodes,
                        edges: store.nexusMap.edges,
                        focusedIds: focusContext?.focusIds ?? [],
                        onSelectNode: handleSelect
                    )
                }
            }
            .id(sceneRefreshKey)
            .ignoresSafeArea()

            // ── Empty / loading state overlay ─────────────────────────────
            if store.nexusMap.nodes.isEmpty {
                VStack(spacing: 14) {
                    if store.nexusMapLoading {
                        ProgressView().controlSize(.large).tint(.white)
                        Text("LOADING UNIVERSE…")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(4)
                            .foregroundColor(.white.opacity(0.8))
                    } else {
                        Image(systemName: "globe")
                            .font(.system(size: 36))
                            .foregroundColor(.white.opacity(0.5))
                        Text("NO DATA")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(4)
                            .foregroundColor(.white.opacity(0.8))
                        Text("nexus-web didn't return any nodes. Tap SYNC to retry.")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 280)
                        Button(action: { Task { await store.fetchNexusMap(); sceneRefreshKey = UUID() } }) {
                            Text("RETRY SYNC")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .tracking(2)
                                .foregroundColor(.black)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .background(Color.white)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // ── Top-left HUD: counts + filters ────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("NEXUS UNIVERSE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(4)
                        .foregroundColor(.primary.opacity(0.85))
                    if store.nexusMapLoading {
                        ProgressView().controlSize(.mini).tint(C.eve)
                    }
                    Text("\(store.nexusMap.nodes.count) NODES · \(store.nexusMap.edges.count) EDGES")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.secondary)
                    Spacer(minLength: 14)
                    // Mode toggle: 2D ⇄ 3D
                    HStack(spacing: 0) {
                        ForEach(NexusMapMode.allCases) { m in
                            Button(action: {
                                mode = m
                                persistedMode = m.rawValue
                                sceneRefreshKey = UUID()
                            }) {
                                Text(m.label)
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .tracking(1.5)
                                    .foregroundColor(mode == m ? .primary : .secondary)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(mode == m ? Color.secondary.opacity(0.18) : Color.clear)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(.ultraThinMaterial)
                    .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.45), lineWidth: 1))
                    .clipShape(Capsule())

                    Button(action: { Task { await store.fetchNexusMap(); sceneRefreshKey = UUID() } }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise").font(.system(size: 9, weight: .bold))
                            Text("SYNC").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.5)
                        }
                        .foregroundColor(C.listen)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(C.listen.opacity(0.12))
                        .overlay(Capsule().strokeBorder(C.listen.opacity(0.4), lineWidth: 1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                // Search
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    TextField("Search the universe…", text: $search)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.9))
                        .frame(width: 280)
                }
                .padding(10)
                .background(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Type filter chips
                HStack(spacing: 4) {
                    ForEach(allTypes, id: \.self) { t in
                        let count = t == "all" ? store.nexusMap.nodes.count : (typeCounts[t] ?? 0)
                        Button(action: { typeFilter = t; sceneRefreshKey = UUID() }) {
                            HStack(spacing: 4) {
                                Circle().fill(NexusMapColors.color(for: t)).frame(width: 6, height: 6)
                                Text(t.uppercased())
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .tracking(1.5)
                                Text("\(count)")
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            .foregroundColor(typeFilter == t ? .primary : .secondary)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .overlay(Capsule().fill(typeFilter == t ? NexusMapColors.color(for: t).opacity(0.18) : Color.clear))
                            )
                            .overlay(Capsule().strokeBorder(typeFilter == t ? NexusMapColors.color(for: t).opacity(0.5) : Color.secondary, lineWidth: 1))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)

            // ── Right side panel: selected node detail ────────────────────
            if let sel = selected {
                let cycle = focusContext?.cycle ?? []
                let cycleCount = cycle.count
                let cycleIdx = cycleIndex
                let isAnchor = (sel.id == anchorId)

                NexusMapDetailPanel(
                    node: sel,
                    isAnchor: isAnchor,
                    cycleIndex: cycleIdx,
                    cycleCount: cycleCount,
                    edges: store.nexusMap.edges,
                    allNodes: store.nexusMap.nodes,
                    onClose: clearFocus,
                    onOpen: {
                        NotificationCenter.default.post(
                            name: .lumenMapNodeOpen,
                            object: nil,
                            userInfo: ["type": sel.type, "id": sel.id]
                        )
                    },
                    onJump: { other in
                        // Clicking a connection in the panel just changes the
                        // panel view — the anchor (focus mode) stays put.
                        withAnimation(.easeInOut(duration: 0.15)) { selected = other }
                    },
                    onPrev: cyclePrev,
                    onNext: cycleNext,
                    onMakeAnchor: {
                        // Promote the currently-viewed node to the new anchor.
                        withAnimation(.easeInOut(duration: 0.2)) {
                            anchorId = sel.id
                        }
                    }
                )
                .frame(width: 420)
                .frame(maxHeight: .infinity)
                .background(.ultraThinMaterial)
                .overlay(Rectangle().frame(width: 1).foregroundColor(NexusMapColors.color(for: sel.type).opacity(0.4)), alignment: .leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: selected?.id)
        .background(mode == .threeD ? Color.black : Color(.windowBackgroundColor))
        .onAppear {
            // Restore persisted mode preference
            if let m = NexusMapMode(rawValue: persistedMode) { mode = m }
        }
        .task {
            if store.nexusMap.nodes.isEmpty {
                await store.fetchNexusMap()
                sceneRefreshKey = UUID()
            }
        }
    }
}

// MARK: - Type → Color mapping (shared)

enum NexusMapColors {
    static func color(for type: String) -> Color {
        switch type {
        case "operation":    return Color(red: 1.0,  green: 0.75, blue: 0.0)   // amber
        case "agent":        return Color(red: 0.22, green: 0.98, blue: 0.49)  // emerald
        case "record":       return Color(red: 1.0,  green: 0.55, blue: 0.4)   // orange
        case "conversation": return Color(red: 0.55, green: 0.36, blue: 0.97) // violet
        case "research":     return Color(red: 0.0,  green: 0.78, blue: 1.0)  // cyan
        case "directive":    return Color(red: 0.96, green: 0.45, blue: 0.85) // pink
        case "topic":        return Color(red: 0.55, green: 0.85, blue: 1.0)  // sky
        case "human":        return Color(red: 1.0,  green: 0.95, blue: 0.5)  // pale yellow
        default:             return Color.primary.opacity(0.6)
        }
    }

    static func nsColor(for type: String) -> NSColor {
        let c = color(for: type)
        return NSColor(c)
    }
}

// MARK: - SceneKit 3D scene

private struct NexusMap3DScene: NSViewRepresentable {
    let nodes: [NexusMapNode]
    let edges: [NexusMapEdge]
    let focusedIds: Set<String>      // anchor + 1-hop neighbors. Empty = no focus.
    let onSelectNode: (NexusMapNode) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelectNode: onSelectNode) }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = NSColor.black
        view.autoenablesDefaultLighting = true
        view.allowsCameraControl = true
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.isJitteringEnabled = true

        // Click handling
        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        view.addGestureRecognizer(click)
        context.coordinator.sceneView = view

        view.scene = buildScene(context: context)
        return view
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        context.coordinator.nodesByName = [:]  // rebuild map
        nsView.scene = buildScene(context: context)
    }

    private func buildScene(context: Context) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = NSColor.black

        // ── Lights ─────────────────────────────────────────────────────────
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = NSColor(white: 0.18, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let key = SCNLight()
        key.type = .omni
        key.color = NSColor.white
        key.intensity = 900
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(0, 0, 800)
        scene.rootNode.addChildNode(keyNode)

        // Background star field
        addStarField(to: scene.rootNode, count: 220)

        // ── Cluster centers — wider spacing so types don't overlap ─────────
        // Scaled up vs. previous version which had clusters overlapping camera.
        let clusterCenters: [String: SCNVector3] = [
            "operation":    SCNVector3(   0,    0,    0),
            "agent":        SCNVector3( 320,  120,    0),
            "record":       SCNVector3(-280,  -80,  120),
            "conversation": SCNVector3(   0, -340,   40),
            "research":     SCNVector3( 120,  280, -160),
            "directive":    SCNVector3(-360,  140, -200),
            "topic":        SCNVector3( 280, -240,  160),
            "human":        SCNVector3(-120,  360,  220),
        ]

        // Place nodes around each cluster center on a sphere of radius
        // proportional to cluster size — tighter than before so nodes don't
        // bleed outside the camera frustum.
        let nodesByType = Dictionary(grouping: nodes, by: \NexusMapNode.type)
        var positions: [String: SCNVector3] = [:]
        var minVec = SCNVector3(x: .infinity, y: .infinity, z: .infinity)
        var maxVec = SCNVector3(x: -.infinity, y: -.infinity, z: -.infinity)

        for (type, list) in nodesByType {
            let center = clusterCenters[type] ?? SCNVector3(0, 0, 0)
            // Cap radius so 268-conversation cluster doesn't swallow camera.
            let radius: CGFloat = min(180, max(50, CGFloat(list.count).squareRoot() * 9))
            for (idx, n) in list.enumerated() {
                let pos = pointOnSphere(center: center, radius: radius, index: idx, total: max(1, list.count))
                positions[n.id] = pos
                minVec = SCNVector3(min(minVec.x, pos.x), min(minVec.y, pos.y), min(minVec.z, pos.z))
                maxVec = SCNVector3(max(maxVec.x, pos.x), max(maxVec.y, pos.y), max(maxVec.z, pos.z))
                let nodeView = makeSceneNode(for: n, at: pos)
                scene.rootNode.addChildNode(nodeView)
                context.coordinator.nodesByName[nodeView.name ?? n.id] = n
            }
        }

        // ── Edges as glowing lines ─────────────────────────────────────────
        for edge in edges {
            guard let a = positions[edge.source], let b = positions[edge.target] else { continue }
            let line = makeEdgeLine(from: a, to: b, color: edgeColor(for: edge.type))
            scene.rootNode.addChildNode(line)
        }

        // ── Auto-fit camera ────────────────────────────────────────────────
        // Position camera based on actual scene bounds so all clusters are
        // visible. Without this the camera was sitting INSIDE the conversation
        // cluster (radius 230pt at origin = empty universe in screenshot).
        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.zNear = 1
        camera.zFar  = 6000
        camera.fieldOfView = 55
        cameraNode.camera = camera

        if positions.isEmpty {
            cameraNode.position = SCNVector3(0, 0, 600)
        } else {
            let cx = (minVec.x + maxVec.x) / 2
            let cy = (minVec.y + maxVec.y) / 2
            let cz = (minVec.z + maxVec.z) / 2
            let extent = max(maxVec.x - minVec.x, max(maxVec.y - minVec.y, maxVec.z - minVec.z))
            // Pull back enough that the largest extent fits in FOV with margin.
            let distance = max(CGFloat(extent) * 1.6, 600)
            cameraNode.position = SCNVector3(CGFloat(cx) + 80, CGFloat(cy) + 60, CGFloat(cz) + distance)
            cameraNode.look(at: SCNVector3(cx, cy, cz))
        }
        scene.rootNode.addChildNode(cameraNode)

        return scene
    }

    private func makeSceneNode(for node: NexusMapNode, at position: SCNVector3) -> SCNNode {
        // Size tied to importance: higher messageCount or pinned = bigger.
        let baseSize: CGFloat = {
            switch node.type {
            case "operation": return 8.0
            case "agent":     return 7.0
            case "human":     return 9.0
            case "directive": return 6.0
            default:          return 4.5
            }
        }()
        let bonus = min(CGFloat(node.messageCount) * 0.08, 5.0) + (node.pinned ? 2.0 : 0)
        let size = baseSize + bonus
        // Focus dim: when there's an active anchor (focusedIds non-empty),
        // anything outside the focus set gets visually muted.
        let focusMuted = !focusedIds.isEmpty && !focusedIds.contains(node.id)
        let dimmed = node.archived || focusMuted

        // Pulse classification (mirrors 2D logic).
        let pulse: NexusMap2DScene.NodePulse = {
            if node.archived { return .dormant }
            let s = (node.status ?? "").lowercased()
            if s == "active" || s == "running" { return .active }
            if ["queued", "in_progress", "in-progress", "scanning"].contains(s) { return .inProgress }
            return .idle
        }()

        // Cube body — tesseract feel.
        let box = SCNBox(width: size * 1.6, height: size * 1.6,
                         length: size * 1.6, chamferRadius: size * 0.18)
        let mat = SCNMaterial()
        let nsColor = NexusMapColors.nsColor(for: node.type)
        mat.diffuse.contents  = nsColor
        mat.emission.contents = nsColor.withAlphaComponent(dimmed ? 0.15 : 0.45)
        mat.specular.contents = NSColor.white
        mat.shininess         = 0.5
        mat.transparency      = dimmed ? 0.45 : 1.0
        box.firstMaterial = mat

        let scn = SCNNode(geometry: box)
        scn.position = position
        scn.name = "node:\(node.id)"

        // Wireframe cage — slightly bigger box, edges only, constant lit.
        let cage = SCNBox(width: size * 2.4, height: size * 2.4,
                          length: size * 2.4, chamferRadius: 0)
        let cageMat = SCNMaterial()
        cageMat.diffuse.contents = NSColor.clear
        cageMat.emission.contents = nsColor.withAlphaComponent(dimmed ? 0.10 : 0.30)
        cageMat.lightingModel = .constant
        cageMat.transparency = 0.6
        cageMat.fillMode = .lines  // wireframe!
        cage.firstMaterial = cageMat
        let cageNode = SCNNode(geometry: cage)
        scn.addChildNode(cageNode)

        // Pulse animations for live nodes.
        switch pulse {
        case .active:
            let pulseScale = SCNAction.sequence([
                SCNAction.scale(to: 1.18, duration: 0.6),
                SCNAction.scale(to: 1.0,  duration: 0.6),
            ])
            scn.runAction(SCNAction.repeatForever(pulseScale))
            // Cage spins to telegraph "live"
            cageNode.runAction(SCNAction.repeatForever(
                SCNAction.rotate(by: .pi * 2, around: SCNVector3(0, 1, 0), duration: 6)
            ))
        case .inProgress:
            // Faster scan-style pulse
            let scan = SCNAction.sequence([
                SCNAction.scale(to: 1.10, duration: 0.35),
                SCNAction.scale(to: 0.95, duration: 0.35),
            ])
            scn.runAction(SCNAction.repeatForever(scan))
            cageNode.runAction(SCNAction.repeatForever(
                SCNAction.rotate(by: .pi * 2, around: SCNVector3(0.3, 1, 0.2), duration: 2.2)
            ))
        case .recent:
            let soft = SCNAction.sequence([
                SCNAction.scale(to: 1.06, duration: 1.2),
                SCNAction.scale(to: 1.0,  duration: 1.2),
            ])
            scn.runAction(SCNAction.repeatForever(soft))
        case .idle, .dormant:
            break
        }

        // Title text floating slightly above (only for major types so we don't
        // overload the scene with 525 labels)
        let labeled: Set<String> = ["operation", "agent", "human", "directive"]
        if !node.title.isEmpty, labeled.contains(node.type) {
            let text = SCNText(string: String(node.title.prefix(32)), extrusionDepth: 0)
            text.font = NSFont.systemFont(ofSize: 8, weight: .medium)
            text.firstMaterial?.diffuse.contents = NSColor.white.withAlphaComponent(0.85)
            text.firstMaterial?.isDoubleSided = true
            text.flatness = 0.4
            let label = SCNNode(geometry: text)
            label.position = SCNVector3(-Float(size), Float(size) + 4, 0)
            label.scale = SCNVector3(0.85, 0.85, 0.85)
            let bb = SCNBillboardConstraint()
            bb.freeAxes = .Y
            label.constraints = [bb]
            scn.addChildNode(label)
        }

        return scn
    }

    private func makeEdgeLine(from a: SCNVector3, to b: SCNVector3, color: NSColor) -> SCNNode {
        let dx = CGFloat(b.x - a.x), dy = CGFloat(b.y - a.y), dz = CGFloat(b.z - a.z)
        let length = sqrt(dx*dx + dy*dy + dz*dz)
        let cyl = SCNCylinder(radius: 0.18, height: length)
        let mat = SCNMaterial()
        mat.diffuse.contents = color.withAlphaComponent(0.05)
        mat.emission.contents = color.withAlphaComponent(0.30)
        mat.transparency = 0.55
        mat.lightingModel = .constant
        cyl.firstMaterial = mat
        let node = SCNNode(geometry: cyl)
        node.position = SCNVector3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2)
        node.look(at: b, up: scnUp, localFront: SCNVector3(0, 1, 0))
        node.castsShadow = false
        return node
    }

    private var scnUp: SCNVector3 { SCNVector3(0, 1, 0) }

    private func pointOnSphere(center: SCNVector3, radius: CGFloat, index: Int, total: Int) -> SCNVector3 {
        // Fibonacci sphere distribution — even coverage, no clumps
        let n = Double(total)
        let i = Double(index) + 0.5
        let phi = acos(1 - 2 * i / n)
        let goldenRatio = (1 + 5.0.squareRoot()) / 2
        let theta = 2 * .pi * i / goldenRatio
        let x = sin(phi) * cos(theta)
        let y = sin(phi) * sin(theta)
        let z = cos(phi)
        return SCNVector3(
            CGFloat(x) * radius + CGFloat(center.x),
            CGFloat(y) * radius + CGFloat(center.y),
            CGFloat(z) * radius + CGFloat(center.z)
        )
    }

    private func edgeColor(for type: String) -> NSColor {
        switch type {
        case "topic-link":          return NSColor.systemPink
        case "temporal":            return NSColor.systemPurple
        case "record-belongs-to":   return NSColor.systemOrange
        case "record-source":       return NSColor.systemTeal
        case "record-parent":       return NSColor.systemYellow
        case "research-on":         return NSColor.cyan
        case "research-producing":  return NSColor.systemGreen
        default:                    return NSColor(white: 0.5, alpha: 0.5)
        }
    }

    private func addStarField(to root: SCNNode, count: Int) {
        for _ in 0..<count {
            let star = SCNSphere(radius: 0.4)
            let mat = SCNMaterial()
            let alpha = 0.3 + Double.random(in: 0...0.4)
            mat.diffuse.contents = NSColor.white.withAlphaComponent(alpha)
            mat.emission.contents = NSColor.white.withAlphaComponent(alpha)
            mat.lightingModel = .constant
            star.firstMaterial = mat
            star.segmentCount = 6
            let node = SCNNode(geometry: star)
            // Place stars on a far sphere
            let phi = Double.random(in: 0...(.pi))
            let theta = Double.random(in: 0...(2 * .pi))
            let R: CGFloat = 1500
            node.position = SCNVector3(
                CGFloat(sin(phi) * cos(theta)) * R,
                CGFloat(sin(phi) * sin(theta)) * R,
                CGFloat(cos(phi)) * R
            )
            root.addChildNode(node)
        }
    }

    final class Coordinator: NSObject {
        weak var sceneView: SCNView?
        var nodesByName: [String: NexusMapNode] = [:]
        let onSelectNode: (NexusMapNode) -> Void

        init(onSelectNode: @escaping (NexusMapNode) -> Void) {
            self.onSelectNode = onSelectNode
        }

        @objc func handleClick(_ recognizer: NSClickGestureRecognizer) {
            guard let view = sceneView else { return }
            let p = recognizer.location(in: view)
            let hits = view.hitTest(p, options: [.searchMode: NSNumber(value: SCNHitTestSearchMode.closest.rawValue)])
            for hit in hits {
                var current: SCNNode? = hit.node
                while let n = current {
                    if let name = n.name, name.hasPrefix("node:"),
                       let model = nodesByName[name] {
                        onSelectNode(model)
                        return
                    }
                    current = n.parent
                }
            }
        }
    }
}

extension Notification.Name {
    static let lumenMapNodeTap  = Notification.Name("lumen.map.nodeTap")
    static let lumenMapNodeOpen = Notification.Name("lumen.map.nodeOpen")
}

// MARK: - Detail Panel (replaces small popup)

private struct NexusMapDetailPanel: View {
    let node: NexusMapNode
    let isAnchor: Bool                 // currently-shown node is the focus anchor
    let cycleIndex: Int                // 0-based position in [anchor, neighbor1, neighbor2, …]
    let cycleCount: Int                // total cycle length (1 = anchor only, no siblings)
    let edges: [NexusMapEdge]
    let allNodes: [NexusMapNode]
    let onClose: () -> Void
    let onOpen: () -> Void
    let onJump: (NexusMapNode) -> Void
    let onPrev: () -> Void
    let onNext: () -> Void
    let onMakeAnchor: () -> Void

    private var connections: [(NexusMapNode, String)] {
        let nodesById = Dictionary(uniqueKeysWithValues: allNodes.map { ($0.id, $0) })
        var out: [(NexusMapNode, String)] = []
        for e in edges {
            if e.source == node.id, let other = nodesById[e.target] {
                out.append((other, e.type))
            } else if e.target == node.id, let other = nodesById[e.source] {
                out.append((other, e.type))
            }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — type pill, anchor badge, close
            HStack(spacing: 8) {
                Circle().fill(NexusMapColors.color(for: node.type)).frame(width: 10, height: 10)
                    .shadow(color: NexusMapColors.color(for: node.type), radius: 4)
                Text(node.type.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2)
                    .foregroundColor(NexusMapColors.color(for: node.type))
                if isAnchor {
                    Text("ANCHOR")
                        .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.5)
                        .foregroundColor(.primary.opacity(0.85))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.primary.opacity(0.12))
                        .clipShape(Capsule())
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 8)

            // Cycle navigator — only meaningful when there's > 1 in the set
            if cycleCount > 1 {
                HStack(spacing: 6) {
                    Button(action: onPrev) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.primary.opacity(0.85))
                            .frame(width: 28, height: 24)
                            .background(Color.secondary.opacity(0.10))
                            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Previous in this neighborhood")

                    Text("\(cycleIndex + 1) / \(cycleCount)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.75))
                        .frame(minWidth: 44)

                    Button(action: onNext) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.primary.opacity(0.85))
                            .frame(width: 28, height: 24)
                            .background(Color.secondary.opacity(0.10))
                            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Next in this neighborhood")

                    Spacer()

                    if !isAnchor {
                        Button(action: onMakeAnchor) {
                            HStack(spacing: 4) {
                                Image(systemName: "scope").font(.system(size: 9, weight: .bold))
                                Text("FOCUS HERE")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.5)
                            }
                            .foregroundColor(NexusMapColors.color(for: node.type))
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(NexusMapColors.color(for: node.type).opacity(0.14))
                            .overlay(Capsule().strokeBorder(NexusMapColors.color(for: node.type).opacity(0.45), lineWidth: 1))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Make this node the new focus anchor")
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 8)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Title
                    Text(node.title.isEmpty ? "Untitled" : node.title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)

                    // Stat row
                    HStack(spacing: 14) {
                        if !node.subtitle.isEmpty {
                            statTile(label: "STATUS", value: node.subtitle)
                        }
                        if node.messageCount > 0 {
                            statTile(label: "MESSAGES", value: "\(node.messageCount)")
                        }
                        if !node.updatedAt.isEmpty {
                            statTile(label: "UPDATED", value: String(node.updatedAt.prefix(10)))
                        }
                    }

                    if node.pinned || node.archived || (node.priority?.isEmpty == false) || (node.status?.isEmpty == false) {
                        HStack(spacing: 6) {
                            if node.pinned { pill("PINNED", color: NexusMapColors.color(for: "directive")) }
                            if node.archived { pill("ARCHIVED", color: .secondary) }
                            if let p = node.priority, !p.isEmpty { pill(p.uppercased(), color: NexusMapColors.color(for: "operation")) }
                            if let s = node.status, !s.isEmpty, s != node.subtitle { pill(s.uppercased(), color: NexusMapColors.color(for: "agent")) }
                        }
                    }

                    if !node.preview.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("PREVIEW")
                                .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2)
                                .foregroundColor(.secondary)
                            Text(node.preview)
                                .font(.system(size: 13))
                                .foregroundColor(.primary.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }

                    if !node.tags.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("TAGS")
                                .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2)
                                .foregroundColor(.secondary)
                            FlowLayout(spacing: 5) {
                                ForEach(node.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundColor(.primary.opacity(0.7))
                                        .padding(.horizontal, 7).padding(.vertical, 3)
                                        .background(Color.secondary.opacity(0.18))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    if !connections.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("CONNECTIONS")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2)
                                    .foregroundColor(.secondary)
                                Text("\(connections.count)")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.primary.opacity(0.7))
                            }
                            ForEach(Array(connections.prefix(12).enumerated()), id: \.offset) { _, conn in
                                Button(action: { onJump(conn.0) }) {
                                    HStack(spacing: 8) {
                                        Circle().fill(NexusMapColors.color(for: conn.0.type))
                                            .frame(width: 7, height: 7)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(conn.0.title.isEmpty ? "Untitled" : conn.0.title)
                                                .font(.system(size: 12))
                                                .foregroundColor(.primary.opacity(0.9))
                                                .lineLimit(1)
                                            Text("\(conn.0.type) · \(conn.1)")
                                                .font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Color.secondary.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                            if connections.count > 12 {
                                Text("+ \(connections.count - 12) more")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 18).padding(.bottom, 18)
            }

            // Footer: open in detail window
            Divider()
            Button(action: onOpen) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.square.fill").font(.system(size: 12, weight: .bold))
                    Text("OPEN IN DETAIL WINDOW")
                        .font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(NexusMapColors.color(for: node.type))
            }
            .buttonStyle(.plain)
        }
    }

    private func statTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.5)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary.opacity(0.85))
                .lineLimit(1)
        }
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.5)
            .foregroundColor(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 1))
            .clipShape(Capsule())
    }
}

// Simple flow layout for tags
private struct FlowLayout: Layout {
    let spacing: CGFloat
    init(spacing: CGFloat = 4) { self.spacing = spacing }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > maxW {
                x = 0; y += rowH + spacing; rowH = 0
            }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX {
                x = bounds.minX; y += rowH + spacing; rowH = 0
            }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

// MARK: - 2D Scene (default mode)
//
// SwiftUI Canvas-based renderer. Pan with drag, zoom with magnification.
// Type-clustered layout: each entity type sits in its own region of the
// 2D plane, with nodes spread inside the cluster on a Fibonacci spiral so
// they don't overlap. Edges drawn as thin lines under nodes; labels visible
// at all zoom levels for major types, only when zoomed in for the rest.

private struct NexusMap2DScene: View {
    let nodes: [NexusMapNode]
    let edges: [NexusMapEdge]
    let selectedId: String?
    let anchorId: String?
    let focusedIds: Set<String>      // anchor + 1-hop neighbors. Empty = no focus.
    let onSelectNode: (NexusMapNode) -> Void

    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    @State private var scaleStart: CGFloat = 1.0

    private static let clusterCenters: [String: CGPoint] = [
        "operation":    CGPoint(x:    0, y:    0),
        "agent":        CGPoint(x:  450, y: -200),
        "record":       CGPoint(x: -380, y:  120),
        "conversation": CGPoint(x:    0, y:  500),
        "research":     CGPoint(x:  280, y:  380),
        "directive":    CGPoint(x: -460, y: -260),
        "topic":        CGPoint(x:  500, y:  140),
        "human":        CGPoint(x: -200, y: -380),
    ]

    private var positions: [String: CGPoint] {
        // Pre-compute node positions: cluster center + Fibonacci spiral offset.
        // Stable ordering means positions don't jiggle on filter changes.
        let grouped = Dictionary(grouping: nodes, by: \.type)
        var out: [String: CGPoint] = [:]
        for (type, list) in grouped {
            let center = Self.clusterCenters[type] ?? .zero
            let radius = max(40, CGFloat(list.count).squareRoot() * 18)
            for (idx, n) in list.enumerated() {
                let golden = (1 + 5.0.squareRoot()) / 2
                let theta = 2 * .pi * Double(idx) / golden
                let r = radius * CGFloat(sqrt(Double(idx) / max(1, Double(list.count))))
                out[n.id] = CGPoint(
                    x: center.x + r * CGFloat(cos(theta)),
                    y: center.y + r * CGFloat(sin(theta))
                )
            }
        }
        return out
    }

    private var nodesById: [String: NexusMapNode] {
        Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
    }

    private func nodeRadius(for n: NexusMapNode) -> CGFloat {
        // Slightly larger than circles so the hex shape is readable.
        let base: CGFloat = {
            switch n.type {
            case "operation": return 12
            case "agent":     return 11
            case "human":     return 13
            case "directive": return 10
            default:          return 8
            }
        }()
        let bonus = min(CGFloat(n.messageCount) * 0.07, 5) + (n.pinned ? 2 : 0)
        return base + bonus
    }

    private static let alwaysLabeled: Set<String> = ["operation", "agent", "human", "directive"]

    /// Animate offset + scale so the focus set fits the viewport. When the
    /// set is empty (focus cleared), restore the default 1× world view.
    private func animateFit(to ids: Set<String>, in viewport: CGSize) {
        let pos = positions
        // Empty focus = reset to home
        if ids.isEmpty {
            withAnimation(.easeInOut(duration: 0.35)) {
                offset = .zero
                dragStart = .zero
                scale = 1.0
                scaleStart = 1.0
            }
            return
        }

        let pts = ids.compactMap { pos[$0] }
        guard !pts.isEmpty else { return }

        let xs = pts.map(\.x), ys = pts.map(\.y)
        let minX = xs.min()!, maxX = xs.max()!
        let minY = ys.min()!, maxY = ys.max()!
        let cx = (minX + maxX) / 2
        let cy = (minY + maxY) / 2

        // Padding so the anchor halo + labels don't get clipped
        let padding: CGFloat = 200
        let bw = max(80, maxX - minX) + padding * 2
        let bh = max(80, maxY - minY) + padding * 2

        // Don't zoom in past 2.0× (gets cartoonish) or out past 0.4×
        let target = min(viewport.width / bw, viewport.height / bh)
        let clamped = max(0.4, min(2.0, target))

        let targetOffset = CGSize(width: -cx * clamped, height: -cy * clamped)
        withAnimation(.easeInOut(duration: 0.45)) {
            offset = targetOffset
            dragStart = targetOffset
            scale = clamped
            scaleStart = clamped
        }
    }

    /// Pulse / signal classification — drives animated treatment in the
    /// Canvas. Active = strong heartbeat, in-progress = scanning, recent =
    /// soft glow, dormant = archived (very dim).
    enum NodePulse { case dormant, active, inProgress, recent, idle }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoFormatterBasic: ISO8601DateFormatter = ISO8601DateFormatter()

    private func pulseFor(_ n: NexusMapNode) -> NodePulse {
        if n.archived { return .dormant }
        let s = (n.status ?? "").lowercased()
        if s == "active" || s == "running" { return .active }
        if ["queued", "in_progress", "in-progress", "scanning"].contains(s) { return .inProgress }
        if let d = Self.isoFormatter.date(from: n.updatedAt) ?? Self.isoFormatterBasic.date(from: n.updatedAt),
           Date().timeIntervalSince(d) < 86400 {
            return .recent
        }
        return .idle
    }

    /// Builds a pointy-top hexagon path centered at `c` with vertex distance `r`.
    private func hexagonPath(center c: CGPoint, radius r: CGFloat) -> Path {
        var path = Path()
        let angles: [Double] = [-90, -30, 30, 90, 150, 210]
        for (i, a) in angles.enumerated() {
            let rad = a * .pi / 180
            let p = CGPoint(x: c.x + r * CGFloat(cos(rad)),
                            y: c.y + r * CGFloat(sin(rad)))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    var body: some View {
        GeometryReader { geo in
            // TimelineView drives steady redraws so pulse animations work
            // inside a Canvas (which is otherwise static between state changes).
            TimelineView(.animation(minimumInterval: 0.05, paused: false)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let slow = sin(t * .pi / 1.2)             // ~2.4s period
                let fast = sin(t * .pi / 0.6)             // ~1.2s period
                let scanPhase = (t.truncatingRemainder(dividingBy: 1.6)) / 1.6  // 0…1 each 1.6s

                Canvas { ctx, size in
                    let cxBase = size.width / 2 + offset.width
                    let cyBase = size.height / 2 + offset.height

                    // World → screen
                    func screen(_ p: CGPoint) -> CGPoint {
                        CGPoint(x: cxBase + p.x * scale, y: cyBase + p.y * scale)
                    }

                    let pos = positions
                    let nById = nodesById

                    // ── Background grid (subtle, only at moderate zoom) ────
                    if scale > 0.55 {
                        let cellSize: CGFloat = 60 * scale
                        let gridAlpha: Double = 0.045
                        let originX = cxBase.truncatingRemainder(dividingBy: cellSize)
                        let originY = cyBase.truncatingRemainder(dividingBy: cellSize)
                        var x = originX
                        while x < size.width {
                            var p = Path()
                            p.move(to: CGPoint(x: x, y: 0))
                            p.addLine(to: CGPoint(x: x, y: size.height))
                            ctx.stroke(p, with: .color(.secondary.opacity(gridAlpha)), lineWidth: 0.5)
                            x += cellSize
                        }
                        var y = originY
                        while y < size.height {
                            var p = Path()
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: size.width, y: y))
                            ctx.stroke(p, with: .color(.secondary.opacity(gridAlpha)), lineWidth: 0.5)
                            y += cellSize
                        }
                    }

                    // Focus mode: when focusedIds is non-empty, dim everything
                    // outside the focus set so the connection web is obvious.
                    let inFocusMode = !focusedIds.isEmpty

                    // ── Edges ───────────────────────────────────────────────
                    // Brighter when either endpoint is active. Static
                    // otherwise so the eye gravitates toward live signal lines.
                    for e in edges {
                        guard let a = pos[e.source], let b = pos[e.target] else { continue }
                        let pA = screen(a), pB = screen(b)
                        let aActive = (nById[e.source].map(pulseFor) ?? .idle) == .active
                        let bActive = (nById[e.target].map(pulseFor) ?? .idle) == .active
                        let live = aActive || bActive
                        var path = Path()
                        path.move(to: pA)
                        path.addLine(to: pB)
                        let inFocus = !inFocusMode || (focusedIds.contains(e.source) && focusedIds.contains(e.target))
                        let edgeAlpha: Double
                        let lw: CGFloat
                        if inFocusMode {
                            // Focus highlight: anchor↔neighbor edges glow; everything else fades way out.
                            if inFocus {
                                edgeAlpha = (e.source == anchorId || e.target == anchorId)
                                    ? 0.7 + 0.20 * slow
                                    : 0.35
                                lw = (e.source == anchorId || e.target == anchorId) ? 1.6 : 0.9
                            } else {
                                edgeAlpha = 0.04
                                lw = 0.4
                            }
                        } else {
                            edgeAlpha = live ? 0.45 + 0.25 * slow : 0.16
                            lw = live ? 1.0 : 0.6
                        }
                        ctx.stroke(path, with: .color(.secondary.opacity(edgeAlpha)), lineWidth: lw)
                    }

                    // ── Hexagonal nodes ────────────────────────────────────
                    for n in nodes {
                        guard let p = pos[n.id] else { continue }
                        let s = screen(p)
                        let r = nodeRadius(for: n)
                        let color = NexusMapColors.color(for: n.type)
                        let isSel = (n.id == selectedId)
                        let isAnchorNode = (n.id == anchorId)
                        let pulse = pulseFor(n)

                        // Focus dim: nodes outside the focus set render at ~0.18 alpha
                        // so the anchor's neighborhood pops without losing global context.
                        let muted = inFocusMode && !focusedIds.contains(n.id)
                        let muteFactor: Double = muted ? 0.22 : 1.0

                        // Animated halo for active / in-progress / recent
                        // (suppressed when muted to keep the focus set the only animated thing)
                        if !muted {
                            switch pulse {
                            case .active:
                                let alpha = (0.20 + 0.18 * (slow * 0.5 + 0.5)) * muteFactor
                                let hr = r * (1.85 + 0.15 * slow)
                                ctx.fill(hexagonPath(center: s, radius: hr),
                                         with: .color(color.opacity(alpha)))
                            case .inProgress:
                                let alpha = (0.18 + 0.22 * (fast * 0.5 + 0.5)) * muteFactor
                                let hr = r * (1.7 + 0.2 * fast)
                                ctx.stroke(hexagonPath(center: s, radius: hr),
                                           with: .color(color.opacity(alpha)),
                                           lineWidth: 1.4)
                            case .recent:
                                let alpha = (0.10 + 0.10 * (slow * 0.5 + 0.5)) * muteFactor
                                let hr = r * 1.6
                                ctx.fill(hexagonPath(center: s, radius: hr),
                                         with: .color(color.opacity(alpha)))
                            case .idle, .dormant:
                                break
                            }
                        }

                        // Anchor halo — extra emphasis on the focused-on node
                        if isAnchorNode {
                            ctx.fill(hexagonPath(center: s, radius: r * 2.6),
                                     with: .color(color.opacity(0.16 + 0.10 * slow)))
                            ctx.stroke(hexagonPath(center: s, radius: r * 2.0),
                                       with: .color(color.opacity(0.55)),
                                       lineWidth: 1.5)
                        }

                        // Selected highlight (drawn under static stroke)
                        if isSel && !isAnchorNode {
                            ctx.fill(hexagonPath(center: s, radius: r * 2.1),
                                     with: .color(color.opacity(0.22 * muteFactor)))
                        }

                        // Outer hex frame (always drawn — the "tile" feel)
                        let bodyAlphaBase = n.archived ? 0.18 : (pulse == .idle ? 0.42 : 0.62)
                        let bodyAlpha = bodyAlphaBase * muteFactor
                        ctx.fill(hexagonPath(center: s, radius: r),
                                 with: .color(color.opacity(bodyAlpha)))
                        ctx.stroke(hexagonPath(center: s, radius: r),
                                   with: .color(color.opacity((n.archived ? 0.35 : 1.0) * muteFactor)),
                                   lineWidth: isSel ? 2.0 : 1.2)

                        // Inner core dot — always-on indicator
                        let coreR = max(1.5, r * 0.30)
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: s.x - coreR, y: s.y - coreR,
                                                    width: coreR * 2, height: coreR * 2)),
                            with: .color(color.opacity((n.archived ? 0.5 : 1.0) * muteFactor))
                        )

                        // In-progress: rotating scan dot inside cell
                        if pulse == .inProgress && !muted {
                            let scanRad = scanPhase * 2 * .pi
                            let scanX = s.x + (r * 0.55) * CGFloat(cos(scanRad))
                            let scanY = s.y + (r * 0.55) * CGFloat(sin(scanRad))
                            ctx.fill(
                                Path(ellipseIn: CGRect(x: scanX - 1.5, y: scanY - 1.5,
                                                        width: 3, height: 3)),
                                with: .color(color)
                            )
                        }

                        // Title rules:
                        //   - Focus mode: always show titles for focus-set nodes
                        //   - Otherwise: major types or zoom > 1.4
                        let showLabel = (inFocusMode && focusedIds.contains(n.id))
                            || Self.alwaysLabeled.contains(n.type)
                            || scale > 1.4
                        if showLabel, !n.title.isEmpty {
                            let label = String(n.title.prefix(28))
                            let text = Text(label)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.primary.opacity(0.85 * muteFactor))
                            ctx.draw(text, at: CGPoint(x: s.x, y: s.y + r + 6), anchor: .top)
                        }
                    }
                }
            }
            .background(Color(.windowBackgroundColor))
            .gesture(
                DragGesture()
                    .onChanged { v in
                        offset = CGSize(
                            width: dragStart.width + v.translation.width,
                            height: dragStart.height + v.translation.height
                        )
                    }
                    .onEnded { _ in dragStart = offset }
            )
            .gesture(
                MagnificationGesture()
                    .onChanged { v in
                        scale = max(0.3, min(4.0, scaleStart * v))
                    }
                    .onEnded { _ in scaleStart = scale }
            )
            .onTapGesture { tapPoint in
                let cx = geo.size.width / 2 + offset.width
                let cy = geo.size.height / 2 + offset.height
                let pos = positions
                // Find nearest node within hit-radius (in screen pixels)
                var bestId: String?
                var bestDist: CGFloat = .infinity
                for n in nodes {
                    guard let p = pos[n.id] else { continue }
                    let s = CGPoint(x: cx + p.x * scale, y: cy + p.y * scale)
                    let dx = s.x - tapPoint.x
                    let dy = s.y - tapPoint.y
                    let d = (dx * dx + dy * dy).squareRoot()
                    let hitR = nodeRadius(for: n) * scale + 4
                    if d < hitR && d < bestDist {
                        bestDist = d
                        bestId = n.id
                    }
                }
                if let id = bestId, let n = nodesById[id] {
                    onSelectNode(n)
                }
            }
            // Auto-fit camera when focus engages: animate offset + scale so the
            // anchor + neighbors fit the viewport with margin. Triggered every
            // time the focus set changes (anchor change or anchor cleared).
            .onChange(of: focusedIds) { _, new in
                animateFit(to: new, in: geo.size)
            }
            .onChange(of: anchorId) { _, _ in
                animateFit(to: focusedIds, in: geo.size)
            }
            .overlay(alignment: .bottomLeading) {
                // Zoom controls + reset
                VStack(spacing: 6) {
                    Button(action: { scale = min(4, scale * 1.25); scaleStart = scale }) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.primary.opacity(0.8))
                            .frame(width: 28, height: 28)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    Button(action: { scale = max(0.3, scale / 1.25); scaleStart = scale }) {
                        Image(systemName: "minus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.primary.opacity(0.8))
                            .frame(width: 28, height: 28)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.25)) {
                            offset = .zero; dragStart = .zero
                            scale = 1.0; scaleStart = 1.0
                        }
                    }) {
                        Image(systemName: "scope")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.primary.opacity(0.8))
                            .frame(width: 28, height: 28)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Reset view")
                    Text(String(format: "%.0f%%", Double(scale * 100)))
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 18).padding(.bottom, 22)
            }
        }
    }
}
