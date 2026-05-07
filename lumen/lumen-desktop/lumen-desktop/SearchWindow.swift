import SwiftUI

// SearchWindow
//
// Standalone window that hosts the SearchPalette. Lets us bind a global
// Cmd-K shortcut to "open search" without touching MainView. The palette
// dismisses itself on selection or ESC; the window closes when the
// presentation flips false.

struct SearchWindow: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var presented: Bool = true
    @State private var lastHit: LumenLocalDB.SearchHit? = nil

    var body: some View {
        ZStack {
            // Click-through dim — the SearchPalette renders its own backdrop
            Color.clear.ignoresSafeArea()
            SearchPalette(isPresented: $presented) { hit in
                lastHit = hit
                // Selection broadcasts via NotificationCenter so any other
                // window (MainView, Console) can route based on hit.kind.
                NotificationCenter.default.post(
                    name: .lumenSearchHit,
                    object: nil,
                    userInfo: ["kind": hit.kind, "id": hit.id, "label": hit.label]
                )
            }
        }
        .frame(minWidth: 660, minHeight: 540)
        .preferredColorScheme(.dark)
        .background(WindowBackground())
        .onChange(of: presented) { _, isPresented in
            // When the user dismisses the palette (ESC, click outside, or
            // selection), close the wrapping window so we don't leave an
            // empty frame behind.
            if !isPresented { dismissWindow(id: "lumen-search") }
        }
        .onAppear { presented = true }
    }
}

extension Notification.Name {
    /// Posted when a SearchPalette hit is selected. UserInfo: kind, id, label.
    /// MainView / Console can listen and route to the appropriate panel.
    static let lumenSearchHit = Notification.Name("lumen.search.hit")
}

/// Transparent NSVisualEffectView so the palette floats nicely without a
/// solid background. Without this the window has the default Mac chrome
/// behind the rounded card and looks awkward.
private struct WindowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
