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
        // Adaptive — follows system theme via C palette.
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

    @State private var email = (UserDefaults.standard.string(forKey: "lumen.lastEmail") ?? "")
    @State private var pin = ""
    @State private var status: PinStatus = .idle
    @State private var errorMsg = ""
    @State private var shakeOffset: CGFloat = 0
    @FocusState private var emailFocused: Bool
    @FocusState private var pinFocused: Bool

    enum PinStatus { case idle, loading, error }

    private let green = Color(red: 0.2, green: 0.9, blue: 0.4)
    private let red   = Color(red: 1.0, green: 0.35, blue: 0.35)

    var body: some View {
        VStack(spacing: 0) {
            backRow
            Spacer()
            VStack(spacing: 24) {
                header
                emailField
                pinDots
                statusLine
            }
            .frame(maxWidth: 320)
            Spacer()
        }
        .background(hiddenPinInput)
        .onAppear {
            // If the Director has logged in here before we have an email
            // cached, jump them straight to the PIN dots. Otherwise focus
            // email so they can type/auto-fill.
            if email.isEmpty { emailFocused = true }
            else { pinFocused = true }
        }
    }

    // MARK: Sub-views

    private var backRow: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                    Text("BACK").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 40).padding(.top, 32)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Sign in")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Email + 4-digit passcode")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    /// Native macOS text field for the identity hint. Locked to lower-case
    /// since emails are stored case-insensitive server-side; saves the
    /// Director from accidentally entering "Patrick@..." vs "patrick@...".
    private var emailField: some View {
        TextField("you@example.com", text: $email)
            .textFieldStyle(.plain)
            .focused($emailFocused)
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                emailFocused ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2),
                lineWidth: 1
            ))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onSubmit { pinFocused = true }
            .onChange(of: email) { _, new in
                email = new.lowercased().trimmingCharacters(in: .whitespaces)
            }
    }

    private var pinDots: some View {
        HStack(spacing: 20) {
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill(i < pin.count
                          ? (status == .error ? red : green)
                          : Color.secondary.opacity(0.25))
                    .frame(width: 14, height: 14)
                    .animation(.easeInOut(duration: 0.1), value: pin.count)
            }
        }
        .offset(x: shakeOffset)
        .padding(.vertical, 6)
        .padding(.horizontal, 14)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(pinFocused ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
        )
    }

    private var statusLine: some View {
        Group {
            if status == .loading {
                Text("Verifying…").foregroundStyle(green)
            } else if status == .error {
                Text(errorMsg).foregroundStyle(red)
            } else {
                Text(" ")
            }
        }
        .font(.system(size: 11))
        .frame(height: 14)
    }

    /// Invisible text field that captures keyboard input for the PIN. Only
    /// focused after the email is set, so digit keystrokes don't compete
    /// with email typing.
    private var hiddenPinInput: some View {
        TextField("", text: Binding(
            get: { pin },
            set: { newValue in
                guard status != .loading else { return }
                let digits = newValue.filter(\.isNumber)
                let trimmed = String(digits.prefix(4))
                pin = trimmed
                if pin.count == 4 { Task { await submitPin() } }
            }
        ))
        .textFieldStyle(.plain)
        .focused($pinFocused)
        .opacity(0.001)
        .frame(width: 1, height: 1)
        .allowsHitTesting(false)
    }

    private func submitPin() async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        guard !trimmedEmail.isEmpty else {
            await fail("EMAIL REQUIRED")
            await MainActor.run { emailFocused = true }
            return
        }
        await MainActor.run { status = .loading }

        let base = LumenAPIManager.shared.nexusBase
        guard let url = URL(string: "\(base)/api/security/pin") else { return }

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

            if http?.statusCode == 200, let sessionId = (json?["sessionId"] as? String) ?? extractCookie(from: http), !sessionId.isEmpty {
                UserDefaults.standard.set(trimmedEmail, forKey: "lumen.lastEmail")
                await MainActor.run { onAuthenticated(sessionId) }
            } else {
                let code = json?["error"] as? String ?? ""
                await fail(code == "IP_BLOCKED" ? "IP BLOCKED — LOCKOUT ACTIVE" : "INVALID CREDENTIALS")
            }
        } catch {
            await fail("CONNECTION ERROR — CHECK NEXUS")
        }
    }

    /// Fallback: if the X-Lumen-Client body field didn't come through,
    /// pull nx_session from the Set-Cookie header.
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

        // Clear stale session cookies before each face auth attempt so a
        // previous session cannot bypass the camera scan.
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
