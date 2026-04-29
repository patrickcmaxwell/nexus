import SwiftUI
import WebKit

// MARK: - Auth Gate (choice screen)

struct AuthGate: View {
    @EnvironmentObject var auth: AuthManager
    @State private var mode: AuthMode = .choose

    enum AuthMode { case choose, pin, face }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            backgroundGrid

            switch mode {
            case .choose: chooseView.transition(.opacity)
            case .pin:
                NativePinView(
                    onAuthenticated: { auth.handleSessionCookie($0) },
                    onBack: { withAnimation { mode = .choose } }
                ).transition(.opacity)
            case .face:
                FaceAuthView(
                    baseURL: LumenAPIManager.shared.nexusBase,
                    onAuthenticated: { auth.handleSessionCookie($0) },
                    onBack: { withAnimation { mode = .choose } }
                ).transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.2), value: mode)
    }

    private var chooseView: some View {
        VStack(spacing: 56) {
            VStack(spacing: 10) {
                Text("LUMEN")
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .tracking(14)
                Text("IDENTITY VERIFICATION REQUIRED")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
                    .tracking(5)
            }

            HStack(spacing: 24) {
                authOption(icon: "lock.fill",  label: "PASSCODE",  sub: "4-DIGIT PIN")   { withAnimation { mode = .pin } }
                authOption(icon: "faceid",     label: "FACE SCAN", sub: "BIOMETRIC ID")  { withAnimation { mode = .face } }
            }
        }
    }

    private func authOption(icon: String, label: String, sub: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 18) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundColor(.white.opacity(0.65))
                VStack(spacing: 5) {
                    Text(label)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                        .tracking(3)
                    Text(sub)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.white.opacity(0.25))
                        .tracking(2)
                }
            }
            .frame(width: 158, height: 136)
            .background(Color.white.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.1), lineWidth: 1))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    private var backgroundGrid: some View {
        Canvas { context, size in
            let spacing: CGFloat = 60
            context.opacity = 0.04
            var x: CGFloat = 0
            while x <= size.width {
                context.stroke(Path { p in p.move(to: .init(x: x, y: 0)); p.addLine(to: .init(x: x, y: size.height)) }, with: .color(.white), lineWidth: 0.5)
                x += spacing
            }
            var y: CGFloat = 0
            while y <= size.height {
                context.stroke(Path { p in p.move(to: .init(x: 0, y: y)); p.addLine(to: .init(x: size.width, y: y)) }, with: .color(.white), lineWidth: 0.5)
                y += spacing
            }
        }.ignoresSafeArea()
    }
}

// MARK: - Native PIN Entry

struct NativePinView: View {
    let onAuthenticated: (String) -> Void
    let onBack: () -> Void

    @State private var pin = ""
    @State private var status: PinStatus = .idle
    @State private var errorMsg = ""
    @State private var shakeOffset: CGFloat = 0

    enum PinStatus { case idle, loading, error }

    private let digits = ["1","2","3","4","5","6","7","8","9","","0","⌫"]
    private let green = Color(red: 0.2, green: 0.9, blue: 0.4)
    private let red   = Color(red: 1.0, green: 0.35, blue: 0.35)

    var body: some View {
        VStack(spacing: 0) {
            backRow

            Spacer()

            VStack(spacing: 36) {
                header
                pinDots
                statusLine
                numpad
            }

            Spacer()
        }
        .onAppear { }
    }

    // MARK: Sub-views

    private var backRow: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                    Text("BACK").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2)
                }
                .foregroundColor(.white.opacity(0.3))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 40).padding(.top, 32)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("PASSCODE")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
                .tracking(6)
            Text("ENTER 4-DIGIT CODE")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.white.opacity(0.2))
                .tracking(3)
        }
    }

    private var pinDots: some View {
        HStack(spacing: 20) {
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill(i < pin.count
                          ? (status == .error ? red : green)
                          : Color.white.opacity(0.12))
                    .frame(width: 14, height: 14)
                    .animation(.easeInOut(duration: 0.1), value: pin.count)
            }
        }
        .offset(x: shakeOffset)
    }

    private var statusLine: some View {
        Group {
            if status == .loading {
                Text("VERIFYING...").foregroundColor(green)
            } else if status == .error {
                Text(errorMsg).foregroundColor(red)
            } else {
                Text(" ")
            }
        }
        .font(.system(size: 9, design: .monospaced))
        .tracking(2)
        .frame(height: 14)
    }

    private var numpad: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(70)), count: 3), spacing: 10) {
            ForEach(digits, id: \.self) { d in
                if d.isEmpty {
                    Color.clear.frame(width: 70, height: 54)
                } else {
                    Button { handleDigit(d) } label: {
                        Text(d)
                            .font(.system(size: d == "⌫" ? 15 : 19, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(d == "⌫" ? 0.45 : 0.8))
                            .frame(width: 70, height: 54)
                            .background(Color.white.opacity(0.04))
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.09), lineWidth: 1))
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                    .disabled(status == .loading)
                }
            }
        }
    }

    // MARK: Logic

    private func handleDigit(_ d: String) {
        guard status != .loading else { return }
        if d == "⌫" { if !pin.isEmpty { pin.removeLast() }; return }
        guard pin.count < 4 else { return }
        pin += d
        if pin.count == 4 { Task { await submitPin() } }
    }

    private func submitPin() async {
        await MainActor.run { status = .loading }

        let base = LumenAPIManager.shared.nexusBase
        guard let url = URL(string: "\(base)/api/security/pin") else { return }

        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("1", forHTTPHeaderField: "X-Lumen-Client")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["pin": pin, "remember": true])

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let http = response as? HTTPURLResponse
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

            if http?.statusCode == 200, let sessionId = json?["sessionId"] as? String, !sessionId.isEmpty {
                await MainActor.run { onAuthenticated(sessionId) }
            } else {
                let code = json?["error"] as? String ?? ""
                await fail(code == "IP_BLOCKED" ? "IP BLOCKED — LOCKOUT ACTIVE" : "INVALID PASSCODE")
            }
        } catch {
            await fail("CONNECTION ERROR — CHECK NEXUS")
        }
    }

    @MainActor
    private func fail(_ msg: String) async {
        errorMsg = msg
        status = .error
        pin = ""
        // Shake animation
        withAnimation(.interpolatingSpring(stiffness: 600, damping: 10)) { shakeOffset = 10 }
        try? await Task.sleep(nanoseconds: 80_000_000)
        withAnimation(.interpolatingSpring(stiffness: 600, damping: 10)) { shakeOffset = -10 }
        try? await Task.sleep(nanoseconds: 80_000_000)
        withAnimation(.interpolatingSpring(stiffness: 600, damping: 10)) { shakeOffset = 0 }
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        status = .idle
    }
}

// MARK: - Face scan wrapper

struct FaceAuthView: View {
    let baseURL: String
    let onAuthenticated: (String) -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                        Text("BACK").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2)
                    }
                    .foregroundColor(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 40).padding(.vertical, 14)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.06)), alignment: .bottom)

            FaceWebView(baseURL: baseURL, onAuthenticated: onAuthenticated)
        }
    }
}

struct FaceWebView: NSViewRepresentable {
    let baseURL: String
    let onAuthenticated: (String) -> Void

    private var startURL: URL { URL(string: "\(baseURL)/auth/face")! }

    func makeCoordinator() -> Coordinator { Coordinator(onAuthenticated: onAuthenticated) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.webView = webView
        webView.load(URLRequest(url: startURL))
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
