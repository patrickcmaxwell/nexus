import SwiftUI
import AppKit

// SearchPalette
//
// Cmd-K-style overlay for unified search across the local cache. Hits
// LumenLocalDB.search(q:) so every keystroke returns results in <50ms even
// with thousands of cached rows — no network round-trips per keypress.
// Spans conversations, operations, records, agents, memories, directives.
//
// Designed to be added to MainView as an overlay:
//
//   .overlay(
//       SearchPalette(isPresented: $showSearch) { hit in
//           // route based on hit.kind / hit.id
//       }
//   )
//
// Wire a Cmd-K keyboard shortcut to flip $showSearch and we're done.

struct SearchPalette: View {
    @Binding var isPresented: Bool
    let onSelect: (LumenLocalDB.SearchHit) -> Void

    @State private var query: String = ""
    @State private var hits: [LumenLocalDB.SearchHit] = []
    @State private var selectionIndex: Int = 0
    @State private var searchTask: Task<Void, Never>? = nil
    @FocusState private var inputFocused: Bool

    var body: some View {
        if isPresented {
            ZStack {
                // Dim backdrop. Tap-to-dismiss.
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }

                paletteCard
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 80)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
            .onAppear {
                inputFocused = true
                if !query.isEmpty { runSearch(query) }
            }
            .onKeyPress(.escape) { dismiss(); return .handled }
            .onKeyPress(.upArrow) {
                if !hits.isEmpty { selectionIndex = max(0, selectionIndex - 1) }
                return .handled
            }
            .onKeyPress(.downArrow) {
                if !hits.isEmpty { selectionIndex = min(hits.count - 1, selectionIndex + 1) }
                return .handled
            }
            .onKeyPress(.return) {
                guard hits.indices.contains(selectionIndex) else { return .handled }
                let hit = hits[selectionIndex]
                onSelect(hit)
                dismiss()
                return .handled
            }
        }
    }

    private var paletteCard: some View {
        VStack(spacing: 0) {
            inputRow
            resultsList
            footer
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.sRGB, red: 0.08, green: 0.09, blue: 0.11, opacity: 0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.cyanAccent.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: Color.cyanAccent.opacity(0.18), radius: 30, y: 4)
    }

    private var inputRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
            TextField("Search across operations, records, agents, memories…", text: $query)
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .onChange(of: query) { _, new in runSearch(new) }
            if !query.isEmpty {
                Button(action: { query = ""; hits = []; selectionIndex = 0 }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
            Text("ESC")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
                .padding(.horizontal, 6).padding(.vertical, 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.white.opacity(0.06)),
            alignment: .bottom
        )
    }

    @ViewBuilder
    private var resultsList: some View {
        if query.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Type to search across all cached datasets")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.45))
                hintRow(symbol: "↑↓", label: "Navigate")
                hintRow(symbol: "↵",  label: "Open the highlighted result")
                hintRow(symbol: "ESC", label: "Dismiss")
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if hits.isEmpty {
            Text("No matches in cache. Try Sync now if results feel stale.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.45))
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(hits.enumerated()), id: \.element.kindAndId) { idx, hit in
                            SearchHitRow(hit: hit, isSelected: idx == selectionIndex)
                                .id(idx)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onSelect(hit)
                                    dismiss()
                                }
                                .onHover { hovering in
                                    if hovering { selectionIndex = idx }
                                }
                        }
                    }
                }
                .frame(maxHeight: 420)
                .onChange(of: selectionIndex) { _, idx in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(idx, anchor: .center)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if !hits.isEmpty {
                Text("\(hits.count) RESULT\(hits.count == 1 ? "" : "S")")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.35))
            }
            Spacer()
            Text("LOCAL CACHE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(Color.cyanAccent.opacity(0.5))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color.white.opacity(0.02))
    }

    private func hintRow(symbol: String, label: String) -> some View {
        HStack(spacing: 10) {
            Text(symbol)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(.white.opacity(0.55))
                .frame(minWidth: 32, alignment: .leading)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    // MARK: - Search runner

    private func runSearch(_ q: String) {
        searchTask?.cancel()
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            hits = []
            selectionIndex = 0
            return
        }
        // Debounce to avoid hammering SQLite on rapid typing — 80ms feels
        // instant but still groups multi-key bursts.
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            if Task.isCancelled { return }
            let results = await LumenLocalDB.shared.search(trimmed, perKind: 8)
            if Task.isCancelled { return }
            await MainActor.run {
                self.hits = results
                self.selectionIndex = 0
            }
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.15)) {
            isPresented = false
        }
        query = ""
        hits = []
        selectionIndex = 0
    }
}

// MARK: - Hit row

private struct SearchHitRow: View {
    let hit: LumenLocalDB.SearchHit
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            kindBadge
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)
                if !hit.snippet.isEmpty {
                    Text(hit.snippet)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(2)
                }
            }
            Spacer()
            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.cyanAccent.opacity(0.8))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(isSelected ? Color.cyanAccent.opacity(0.08) : Color.clear)
        .overlay(
            Rectangle()
                .frame(width: 2)
                .foregroundColor(isSelected ? Color.cyanAccent : .clear),
            alignment: .leading
        )
    }

    private var kindBadge: some View {
        let (icon, color) = badgeStyle(for: hit.kind)
        return Image(systemName: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(color)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(color.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(color.opacity(0.35), lineWidth: 1)
            )
    }

    private func badgeStyle(for kind: String) -> (icon: String, color: Color) {
        switch kind {
        case "conversation": return ("bubble.left.and.bubble.right.fill", Color.cyanAccent)
        case "operation":    return ("flowchart.fill", Color(.sRGB, red: 0.95, green: 0.55, blue: 0.30, opacity: 1))
        case "record":       return ("doc.text.fill", Color(.sRGB, red: 0.85, green: 0.75, blue: 0.30, opacity: 1))
        case "agent":        return ("brain.head.profile", Color(.sRGB, red: 0.65, green: 0.45, blue: 0.95, opacity: 1))
        case "memory":       return ("sparkles", Color(.sRGB, red: 0.45, green: 0.85, blue: 0.65, opacity: 1))
        case "directive":    return ("scroll.fill", Color(.sRGB, red: 0.95, green: 0.45, blue: 0.65, opacity: 1))
        default:             return ("circle.fill", .white.opacity(0.4))
        }
    }
}

// LumenLocalDB.SearchHit is Sendable but not Identifiable — give it a key
// for ForEach without polluting the public type with conformance.
private extension LumenLocalDB.SearchHit {
    var kindAndId: String { "\(kind):\(id)" }
}

// MARK: - Color shorthand

private extension Color {
    static let cyanAccent = Color(.sRGB, red: 0.40, green: 0.85, blue: 1.00, opacity: 1)
}
