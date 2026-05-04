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

struct NexusMapView: View {
    @ObservedObject var store: LumenStore
    @State private var search: String = ""
    @State private var typeFilter: String = "all"
    @State private var selected: NexusMapNode?
    @State private var sceneRefreshKey = UUID()  // re-creates scene when filter/data changes

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

    var body: some View {
        ZStack(alignment: .topLeading) {
            NexusMap3DScene(
                nodes: filteredNodes,
                edges: store.nexusMap.edges,
                onSelectNode: { node in
                    selected = node
                    NotificationCenter.default.post(
                        name: .lumenMapNodeTap,
                        object: nil,
                        userInfo: ["type": node.type, "id": node.id]
                    )
                }
            )
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

            // ── Bottom-right: selected node card ──────────────────────────
            if let sel = selected {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Circle().fill(NexusMapColors.color(for: sel.type)).frame(width: 8, height: 8)
                        Text(sel.type.uppercased())
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(NexusMapColors.color(for: sel.type))
                        Spacer()
                        Button(action: { selected = nil }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Text(sel.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.95))
                        .lineLimit(2)
                    if !sel.subtitle.isEmpty {
                        Text(sel.subtitle)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    if !sel.preview.isEmpty {
                        Text(sel.preview)
                            .font(.system(size: 12))
                            .foregroundColor(.primary.opacity(0.7))
                            .lineLimit(4)
                    }
                    if !sel.tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(sel.tags.prefix(5), id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                                    .foregroundColor(.primary.opacity(0.6))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.secondary)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    HStack {
                        Text("Updated \(sel.updatedAt.prefix(10))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: {
                            NotificationCenter.default.post(
                                name: .lumenMapNodeOpen,
                                object: nil,
                                userInfo: ["type": sel.type, "id": sel.id]
                            )
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.right.square").font(.system(size: 10, weight: .bold))
                                Text("OPEN").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.5)
                            }
                            .foregroundColor(C.eve)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(C.eve.opacity(0.15))
                            .overlay(Capsule().strokeBorder(C.eve.opacity(0.5), lineWidth: 1))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
                .frame(width: 360)
                .background(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(NexusMapColors.color(for: sel.type).opacity(0.5), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .background(Color.black)
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
        // Bumped from previous (2.4-4.5) so nodes are visible at auto-fit
        // camera distances of 600+ units.
        let baseRadius: CGFloat = {
            switch node.type {
            case "operation": return 8.0
            case "agent":     return 7.0
            case "human":     return 9.0
            case "directive": return 6.0
            default:          return 4.5
            }
        }()
        let bonus = min(CGFloat(node.messageCount) * 0.08, 5.0) + (node.pinned ? 2.0 : 0)
        let radius = baseRadius + bonus
        let dimmed = node.archived

        let sphere = SCNSphere(radius: radius)
        sphere.segmentCount = 20

        let mat = SCNMaterial()
        let nsColor = NexusMapColors.nsColor(for: node.type)
        mat.diffuse.contents  = nsColor
        mat.emission.contents = nsColor.withAlphaComponent(dimmed ? 0.15 : 0.55)
        mat.specular.contents = NSColor.white
        mat.shininess         = 0.4
        mat.transparency      = dimmed ? 0.45 : 1.0
        sphere.firstMaterial  = mat

        let scn = SCNNode(geometry: sphere)
        scn.position = position
        scn.name = "node:\(node.id)"

        // Halo glow
        let halo = SCNSphere(radius: radius * 1.6)
        let haloMat = SCNMaterial()
        haloMat.diffuse.contents = NSColor.clear
        haloMat.emission.contents = nsColor.withAlphaComponent(0.18)
        haloMat.transparency = 0.25
        halo.firstMaterial = haloMat
        halo.segmentCount = 14
        let haloNode = SCNNode(geometry: halo)
        scn.addChildNode(haloNode)

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
            label.position = SCNVector3(-Float(radius), Float(radius) + 4, 0)
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
