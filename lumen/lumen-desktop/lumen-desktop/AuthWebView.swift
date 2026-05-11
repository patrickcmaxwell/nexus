import SwiftUI
import WebKit

// MARK: - AuthGate
//
// Unified entry point. One screen, one card, two modes (passcode or face)
// toggled by a pill control — no orphan sub-views, no buried back chevrons.
// Resolves the API base URL on appear so a stale localhost doesn't strand
// the user on a "CONNECTION ERROR" screen they can't navigate away from.

struct AuthGate: View {
    @EnvironmentObject var auth: AuthManager
    // Default to face mode — face capture is the primary verification path
    // for this device. Passcode remains available via the pill toggle as a
    // fallback when the camera is unusable or face match fails.
    @State private var mode: Mode = .face
    @State private var hostStatus: HostStatus = .resolving

    enum Mode { case passcode, face }
    enum HostStatus: Equatable { case resolving, ready(String), unreachable }

    var body: some View {
        ZStack {
            background
            card
        }
        .task { await resolveHost() }
        .preferredColorScheme(.dark)
    }

    // MARK: Background

    private var background: some View {
        ZStack {
            Color(.sRGB, red: 0.04, green: 0.05, blue: 0.07, opacity: 1).ignoresSafeArea()

            // Soft radial cyan glow behind the card
            RadialGradient(
                colors: [Color.cyanAccent.opacity(0.10), .clear],
                center: .center,
                startRadius: 40,
                endRadius: 360
            )
            .ignoresSafeArea()
            .blendMode(.plusLighter)

            // Subtle grid
            Canvas { ctx, size in
                let spacing: CGFloat = 56
                ctx.opacity = 0.06
                var x: CGFloat = 0
                while x <= size.width {
                    ctx.stroke(Path { p in p.move(to: .init(x: x, y: 0)); p.addLine(to: .init(x: x, y: size.height)) }, with: .color(.white), lineWidth: 0.5)
                    x += spacing
                }
                var y: CGFloat = 0
                while y <= size.height {
                    ctx.stroke(Path { p in p.move(to: .init(x: 0, y: y)); p.addLine(to: .init(x: size.width, y: y)) }, with: .color(.white), lineWidth: 0.5)
                    y += spacing
                }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Card

    private var card: some View {
        VStack(spacing: 28) {
            header
            modeToggle
            content
            hostBanner
        }
        .padding(32)
        .frame(maxWidth: 440)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.cyanAccent.opacity(0.25), lineWidth: 1)
                )
        )
        .overlay(corners)
        .shadow(color: Color.cyanAccent.opacity(0.15), radius: 40, y: 4)
    }

    private var corners: some View {
        let bracket = Color.cyanAccent.opacity(0.55)
        return ZStack {
            VStack {
                HStack {
                    cornerBracket(corner: .topLeading,  color: bracket)
                    Spacer()
                    cornerBracket(corner: .topTrailing, color: bracket)
                }
                Spacer()
                HStack {
                    cornerBracket(corner: .bottomLeading,  color: bracket)
                    Spacer()
                    cornerBracket(corner: .bottomTrailing, color: bracket)
                }
            }
        }
        .padding(2)
    }

    private func cornerBracket(corner: UnitPoint, color: Color) -> some View {
        let size: CGFloat = 14
        let stroke: CGFloat = 1.5
        return ZStack {
            switch corner {
            case .topLeading:
                Path { p in p.move(to: .init(x: 0, y: size)); p.addLine(to: .zero); p.addLine(to: .init(x: size, y: 0)) }
                    .stroke(color, lineWidth: stroke)
            case .topTrailing:
                Path { p in p.move(to: .init(x: 0, y: 0)); p.addLine(to: .init(x: size, y: 0)); p.addLine(to: .init(x: size, y: size)) }
                    .stroke(color, lineWidth: stroke)
            case .bottomLeading:
                Path { p in p.move(to: .init(x: 0, y: 0)); p.addLine(to: .init(x: 0, y: size)); p.addLine(to: .init(x: size, y: size)) }
                    .stroke(color, lineWidth: stroke)
            case .bottomTrailing:
                Path { p in p.move(to: .init(x: size, y: 0)); p.addLine(to: .init(x: size, y: size)); p.addLine(to: .init(x: 0, y: size)) }
                    .stroke(color, lineWidth: stroke)
            default: EmptyView()
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.cyanAccent)
                    .frame(width: 6, height: 6)
                    .shadow(color: Color.cyanAccent, radius: 4)
                Text("LUMEN")
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .tracking(8)
                    .foregroundColor(.white.opacity(0.95))
            }
            Text("Sign in to Nexus")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.55))
        }
    }

    // MARK: Mode toggle

    private var modeToggle: some View {
        HStack(spacing: 0) {
            toggleButton(label: "PASSCODE", icon: "lock.fill", isOn: mode == .passcode) {
                withAnimation(.easeInOut(duration: 0.2)) { mode = .passcode }
            }
            toggleButton(label: "FACE", icon: "faceid", isOn: mode == .face) {
                withAnimation(.easeInOut(duration: 0.2)) { mode = .face }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func toggleButton(label: String, icon: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .medium))
                Text(label).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2)
            }
            .foregroundColor(isOn ? Color.cyanAccent : .white.opacity(0.45))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isOn ? Color.cyanAccent.opacity(0.12) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isOn ? Color.cyanAccent.opacity(0.5) : .clear, lineWidth: 1)
            )
            .padding(2)
        }
        .buttonStyle(.plain)
    }

    // MARK: Content (per mode)

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .passcode:
            PasscodePanel(
                hostReady: hostStatus.isReady,
                onAuthenticated: { auth.handleSessionCookie($0) }
            )
        case .face:
            FacePanel(
                baseURL: hostStatus.baseURL ?? LumenAPIManager.shared.nexusBase,
                hostReady: hostStatus.isReady,
                onAuthenticated: { auth.handleSessionCookie($0) }
            )
        }
    }

    // MARK: Host banner

    @ViewBuilder
    private var hostBanner: some View {
        switch hostStatus {
        case .resolving:
            statusPill(text: "CONNECTING TO NEXUS…", color: .white.opacity(0.4), pulse: true)
        case .ready(let host):
            statusPill(
                text: host.contains("localhost") ? "LOCAL DEV" : "NEXUS ONLINE",
                color: Color.greenAccent,
                pulse: false
            )
        case .unreachable:
            VStack(spacing: 6) {
                statusPill(text: "NEXUS UNREACHABLE", color: Color.redAccent, pulse: false)
                Button("Retry") { Task { await resolveHost() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.cyanAccent)
            }
        }
    }

    private func statusPill(text: String, color: Color, pulse: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
                .opacity(pulse ? 0.6 : 1)
                .scaleEffect(pulse ? 1.0 : 1.0)
                .modifier(PulseModifier(active: pulse))
            Text(text)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(color.opacity(0.85))
        }
    }

    // MARK: Host resolution

    private func resolveHost() async {
        await MainActor.run { hostStatus = .resolving }
        let resolved = await LumenAPIManager.shared.resolveBaseURL()
        // Verify the resolved host actually responds to /api/dashboard/overview.
        // Local probe in resolveBaseURL() falls through to remote; if remote is
        // also down we want to show an explicit "unreachable" state instead of
        // pretending we have a host.
        if let url = URL(string: "\(resolved)/api/dashboard/overview") {
            var req = URLRequest(url: url, timeoutInterval: 4)
            req.httpMethod = "HEAD"
            do {
                let (_, response) = try await URLSession.shared.data(for: req)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                // Any HTTP response (200, 401, 404) means the host is alive —
                // 401 is expected without a session cookie.
                if (200...499).contains(code) {
                    await MainActor.run { hostStatus = .ready(resolved) }
                    return
                }
            } catch {
                // Fall through to unreachable
            }
        }
        await MainActor.run { hostStatus = .unreachable }
    }
}

private extension AuthGate.HostStatus {
    var isReady: Bool { if case .ready = self { return true } else { return false } }
    var baseURL: String? { if case .ready(let h) = self { return h } else { return nil } }
}

// MARK: - Passcode panel

private struct PasscodePanel: View {
    let hostReady: Bool
    let onAuthenticated: (String) -> Void

    @State private var email = (UserDefaults.standard.string(forKey: "lumen.lastEmail") ?? "")
    @State private var pin = ""
    @State private var status: Status = .idle
    @State private var errorMsg = ""
    @State private var shake: CGFloat = 0
    @FocusState private var emailFocused: Bool
    @FocusState private var pinFocused: Bool

    enum Status { case idle, loading, error, success }

    var body: some View {
        VStack(spacing: 18) {
            emailField
            pinDots
            statusLine
            submitButton
        }
        .onAppear {
            // Hand focus to whichever field needs it. If we have a remembered
            // email, the PIN is the next thing the user wants — focus it
            // directly so they can start typing immediately.
            if email.isEmpty { emailFocused = true } else { pinFocused = true }
        }
    }

    private var emailField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EMAIL")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(.white.opacity(0.4))
            TextField("you@example.com", text: $email)
                .textFieldStyle(.plain)
                .focused($emailFocused)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(emailFocused ? Color.cyanAccent.opacity(0.55) : Color.white.opacity(0.12), lineWidth: 1)
                )
                .onSubmit { pinFocused = true }
                .onChange(of: email) { _, new in
                    let normalized = new.lowercased().trimmingCharacters(in: .whitespaces)
                    if normalized != email { email = normalized }
                }
        }
    }

    private var pinDots: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PASSCODE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(.white.opacity(0.4))

            // Whole row is one tappable hit area that focuses the hidden field
            ZStack {
                HStack(spacing: 12) {
                    ForEach(0..<4, id: \.self) { i in
                        let filled = i < pin.count
                        let color: Color = {
                            if status == .error { return .redAccent }
                            if filled { return .cyanAccent }
                            return .white.opacity(0.25)
                        }()
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(filled ? color.opacity(0.18) : Color.white.opacity(0.04))
                            .frame(height: 48)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(
                                        filled ? color.opacity(0.7)
                                               : (i == pin.count && pinFocused ? Color.cyanAccent.opacity(0.5) : Color.white.opacity(0.12)),
                                        lineWidth: 1
                                    )
                            )
                            .overlay(
                                Group {
                                    if filled {
                                        Circle().fill(color).frame(width: 8, height: 8)
                                    }
                                }
                            )
                            .animation(.easeOut(duration: 0.12), value: filled)
                    }
                }
                .offset(x: shake)

                // Hidden secure field captures all keystrokes when row is focused
                SecureField("", text: Binding(
                    get: { pin },
                    set: { newValue in
                        guard status != .loading else { return }
                        let digits = newValue.filter(\.isNumber)
                        let trimmed = String(digits.prefix(4))
                        if trimmed != pin {
                            pin = trimmed
                            if pin.count == 4 { Task { await submit() } }
                        }
                    }
                ))
                .textFieldStyle(.plain)
                .focused($pinFocused)
                .opacity(0.001)
                .frame(height: 48)
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onTapGesture { pinFocused = true }
        }
    }

    private var statusLine: some View {
        Group {
            switch status {
            case .loading:
                Text("VERIFYING…")
                    .foregroundColor(Color.cyanAccent.opacity(0.85))
            case .error:
                Text(errorMsg)
                    .foregroundColor(Color.redAccent.opacity(0.9))
            case .success:
                Text("ACCESS GRANTED")
                    .foregroundColor(Color.greenAccent)
            case .idle:
                Text(" ")
            }
        }
        .font(.system(size: 10, weight: .bold, design: .monospaced))
        .tracking(2)
        .frame(height: 14)
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: 8) {
                if status == .loading {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: "arrow.right").font(.system(size: 12, weight: .bold))
                }
                Text("UNLOCK NEXUS")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(2)
            }
            .foregroundColor(canSubmit ? Color.cyanAccent : .white.opacity(0.3))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(canSubmit ? Color.cyanAccent.opacity(0.12) : Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(canSubmit ? Color.cyanAccent.opacity(0.55) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
    }

    private var canSubmit: Bool {
        hostReady && status != .loading && !email.isEmpty && pin.count == 4
    }

    // MARK: Submit

    private func submit() async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        guard !trimmedEmail.isEmpty else {
            await fail("EMAIL REQUIRED")
            await MainActor.run { emailFocused = true }
            return
        }
        guard pin.count == 4 else {
            await fail("ENTER 4-DIGIT PASSCODE")
            return
        }
        await MainActor.run { status = .loading }

        let base = LumenAPIManager.shared.nexusBase
        guard let url = URL(string: "\(base)/api/security/pin") else {
            await fail("INVALID HOST")
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("1", forHTTPHeaderField: "X-Lumen-Client")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "email": trimmedEmail,
            "pin": pin,
            "remember": true,
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let http = response as? HTTPURLResponse
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

            if http?.statusCode == 200,
               let sessionId = (json?["sessionId"] as? String) ?? extractCookie(from: http),
               !sessionId.isEmpty {
                UserDefaults.standard.set(trimmedEmail, forKey: "lumen.lastEmail")
                await MainActor.run { status = .success }
                try? await Task.sleep(nanoseconds: 250_000_000)
                await MainActor.run { onAuthenticated(sessionId) }
            } else {
                let code = json?["error"] as? String ?? ""
                await fail(code == "IP_BLOCKED" ? "IP BLOCKED — LOCKOUT" : "INVALID CREDENTIALS")
            }
        } catch {
            await fail("CONNECTION ERROR")
        }
    }

    private func extractCookie(from http: HTTPURLResponse?) -> String? {
        guard let header = http?.value(forHTTPHeaderField: "Set-Cookie") else { return nil }
        for part in header.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count == 2, kv[0] == "nx_session" {
                return kv[1]
            }
        }
        return nil
    }

    @MainActor
    private func fail(_ msg: String) async {
        errorMsg = msg
        status = .error
        pin = ""
        withAnimation(.interpolatingSpring(stiffness: 600, damping: 10)) { shake = 10 }
        try? await Task.sleep(nanoseconds: 80_000_000)
        withAnimation(.interpolatingSpring(stiffness: 600, damping: 10)) { shake = -10 }
        try? await Task.sleep(nanoseconds: 80_000_000)
        withAnimation(.interpolatingSpring(stiffness: 600, damping: 10)) { shake = 0 }
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        if status == .error { status = .idle }
    }
}

// MARK: - Face panel

private struct FacePanel: View {
    let baseURL: String
    let hostReady: Bool
    let onAuthenticated: (String) -> Void

    // 100% native — AVFoundation camera + Vision face detection in Swift,
    // descriptor compute happens server-side via /api/security/face/match
    // (face-api.js + tfjs-node). No WebView, no embedded page chrome.
    var body: some View {
        ZStack {
            if hostReady {
                NativeFaceCaptureView(baseURL: baseURL, onAuthenticated: onAuthenticated)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "wifi.slash").font(.system(size: 24))
                                .foregroundColor(.white.opacity(0.35))
                            Text("WAITING FOR NEXUS")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .tracking(2)
                                .foregroundColor(.white.opacity(0.45))
                        }
                    )
                    .frame(height: 360)
            }
        }
    }
}

// MARK: - Face WebView

struct FaceWebView: NSViewRepresentable {
    let baseURL: String
    var embedded: Bool = false
    let onAuthenticated: (String) -> Void

    // ?embedded=1 tells the page to drop its standalone chrome and auto-run
    // the scan; the desktop wrapper supplies the surrounding card UI.
    private var startURL: URL {
        URL(string: "\(baseURL)/auth/face\(embedded ? "?embedded=1" : "")")!
    }

    func makeCoordinator() -> Coordinator { Coordinator(onAuthenticated: onAuthenticated) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.webView = webView

        // Wipe any stale auth cookies before starting the face flow so we
        // can't bypass the camera scan with a leftover session.
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let store = webView.configuration.websiteDataStore.httpCookieStore
            let group = DispatchGroup()
            cookies.filter { $0.name == "nx_session" || $0.name == "mn_pin_verified" || $0.name == "mn_face_verified" }
                   .forEach { cookie in
                       group.enter()
                       store.delete(cookie) { group.leave() }
                   }
            group.notify(queue: .main) {
                webView.load(URLRequest(url: startURL))
            }
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let onAuthenticated: (String) -> Void
        weak var webView: WKWebView?
        private var timer: Timer?
        private var authenticated = false

        init(onAuthenticated: @escaping (String) -> Void) {
            self.onAuthenticated = onAuthenticated
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            timer?.invalidate()
            var attempts = 0
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
                guard let self, let webView = self.webView else { t.invalidate(); return }
                attempts += 1
                self.checkForSession(in: webView)
                if attempts >= 20 { t.invalidate() }
            }
        }

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
                    self.timer?.invalidate()
                    DispatchQueue.main.async { self.onAuthenticated(session.value) }
                }
            }
        }
    }
}

// MARK: - Helpers

private struct PulseModifier: ViewModifier {
    let active: Bool
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .opacity(active ? (on ? 1.0 : 0.4) : 1.0)
            .onAppear {
                guard active else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    on.toggle()
                }
            }
    }
}

private extension Color {
    static let cyanAccent  = Color(.sRGB, red: 0.40, green: 0.85, blue: 1.00, opacity: 1)
    static let greenAccent = Color(.sRGB, red: 0.30, green: 0.92, blue: 0.55, opacity: 1)
    static let redAccent   = Color(.sRGB, red: 1.00, green: 0.42, blue: 0.42, opacity: 1)
}
