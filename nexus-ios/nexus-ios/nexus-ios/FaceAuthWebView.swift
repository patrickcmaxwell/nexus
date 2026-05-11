// FaceAuthWebView.swift
// Cross-device face authentication, mirroring Lumen Desktop's FaceWebView.
// Embeds nexus-web's existing /auth/face?embedded=1 page in a WKWebView so
// the face-api.js descriptor extraction code that already runs in the
// browser is reused here byte-for-byte. After the page successfully posts
// to /api/security/face and receives the `nx_session` cookie, we extract
// it from the WKWebView's cookie store and hand it back to NexusAPIClient
// as the active sessionId.
//
// Why this path (not on-device descriptors): the server's match threshold
// is calibrated to face-api.js's 128-d ResNet output. Generating a
// compatible descriptor on-device would need the same model exported to
// Core ML — non-trivial, and re-running drift across the iOS / web /
// desktop trio is exactly the bug we're avoiding by reusing the web flow.
//
// Camera permission is granted programmatically via WKUIDelegate's
// `requestMediaCapturePermissionFor` so the embedded page doesn't need
// the user to tap a separate confirm prompt — they already chose face
// auth by tapping FACE.

import SwiftUI
import WebKit

struct FaceAuthWebView: UIViewRepresentable {
    let baseURL: String
    var embedded: Bool = true
    let onAuthenticated: (String) -> Void

    private var startURL: URL {
        URL(string: "\(baseURL)/auth/face\(embedded ? "?embedded=1" : "")")!
    }

    func makeCoordinator() -> Coordinator { Coordinator(onAuthenticated: onAuthenticated) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Skip the gesture-required gate so the embedded page can call
        // navigator.mediaDevices.getUserMedia immediately.
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        context.coordinator.webView = webView

        // Wipe stale auth cookies before starting so a leftover nx_session
        // can't shortcut the camera scan. Same belt-and-suspenders
        // posture the desktop uses.
        let store = webView.configuration.websiteDataStore.httpCookieStore
        store.getAllCookies { cookies in
            let group = DispatchGroup()
            cookies.filter { ["nx_session", "mn_pin_verified", "mn_face_verified"].contains($0.name) }
                .forEach { c in
                    group.enter()
                    store.delete(c) { group.leave() }
                }
            group.notify(queue: .main) {
                webView.load(URLRequest(url: startURL))
            }
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let onAuthenticated: (String) -> Void
        weak var webView: WKWebView?
        private var pollTimer: Timer?
        private var authenticated = false

        init(onAuthenticated: @escaping (String) -> Void) {
            self.onAuthenticated = onAuthenticated
        }

        deinit { pollTimer?.invalidate() }

        // After every navigation completes, poll the cookie jar for up to
        // 20 seconds looking for a fresh `nx_session`. The face page lives
        // at /auth/face and on success it does router.push to /dashboard,
        // which our matcher catches on either page since cookies are
        // domain-level.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pollTimer?.invalidate()
            var attempts = 0
            pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
                guard let self, let webView = self.webView else { t.invalidate(); return }
                attempts += 1
                self.checkForSession(in: webView)
                if attempts >= 25 { t.invalidate() }
            }
        }

        // Auto-grant camera permission requested by the embedded page.
        // The host iOS app already declared NSCameraUsageDescription and
        // the user explicitly tapped FACE to land here — no second prompt.
        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            decisionHandler(.grant)
        }

        private func checkForSession(in webView: WKWebView) {
            guard !authenticated else { return }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.authenticated else { return }
                if let session = cookies.first(where: { $0.name == "nx_session" }) {
                    self.authenticated = true
                    self.pollTimer?.invalidate()
                    DispatchQueue.main.async { self.onAuthenticated(session.value) }
                }
            }
        }
    }
}

// MARK: - SwiftUI presentation wrapper

/// Full-screen face capture sheet. Presents a header + close button, the
/// WebView fills the rest. Designed to be shown from PinAuthView when the
/// user taps the FACE toggle.
struct FaceAuthSheet: View {
    let baseURL: String
    let onAuth: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("FACE AUTHENTICATION")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.indigo)
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(8)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 6)

                FaceAuthWebView(baseURL: baseURL) { sessionId in
                    onAuth(sessionId)
                    dismiss()
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .preferredColorScheme(.dark)
    }
}
