// PresenceLockView.swift
//
// The curtain that drops in front of MainView when `LumenPresenceMonitor.isLocked`
// flips true. Looks similar to AuthGate but its job is narrower: the user
// is already known, we just need to confirm "yes, still me." Two unlock
// paths, same as launch:
//
//   1. Face capture — embeds NativeFaceCaptureView. On match the server
//      returns a fresh session cookie which we adopt (refreshes the
//      session anyway, which is a useful side-effect) and then dismiss
//      the curtain.
//
//   2. Passcode fallback — pre-fills email from `lumen.lastEmail` so the
//      user only has to type the PIN. POSTs to /api/security/pin and
//      adopts the returned cookie.
//
// What this view does NOT do: tear down sync, voice timers, terminal
// bridge, etc. Those keep running underneath. The curtain only blocks
// the UI from being seen / driven by whoever is at the keyboard.

import SwiftUI

struct PresenceLockView: View {
    @EnvironmentObject var presence: LumenPresenceMonitor
    @EnvironmentObject var auth: AuthManager

    @State private var mode: Mode = .face
    @State private var pin: String = ""
    @State private var pinError: String = ""
    @State private var pinSubmitting: Bool = false
    @FocusState private var pinFocused: Bool

    enum Mode { case face, passcode }

    var body: some View {
        ZStack {
            // Opaque blackout — anything behind this is gone from view.
            // We do NOT use a translucent material here on purpose: the
            // whole point is "no one can see the app."
            Color.black.opacity(0.96).ignoresSafeArea()

            // Subtle grid + radial glow so it still feels like Lumen, not
            // a kernel panic.
            grid.ignoresSafeArea().opacity(0.5)

            VStack(spacing: 24) {
                header
                modeToggle
                content
                hint
            }
            .padding(32)
            .frame(maxWidth: 420)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color(.sRGB, red: 0.40, green: 0.85, blue: 1.00, opacity: 0.35), lineWidth: 1)
                    )
            )
            .shadow(color: Color(.sRGB, red: 0.40, green: 0.85, blue: 1.00, opacity: 0.18), radius: 30, y: 4)
        }
        .preferredColorScheme(.dark)
        .transition(.opacity)
    }

    private var grid: some View {
        Canvas { ctx, size in
            let spacing: CGFloat = 60
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
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(Color(.sRGB, red: 0.40, green: 0.85, blue: 1.00, opacity: 1))
            Text("LUMEN LOCKED")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(4)
                .foregroundColor(.white.opacity(0.85))
            Text(presence.lastLockReason.rawValue)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))
                .multilineTextAlignment(.center)
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 0) {
            toggleButton("FACE", icon: "faceid", isOn: mode == .face) {
                withAnimation(.easeInOut(duration: 0.15)) { mode = .face }
            }
            toggleButton("PASSCODE", icon: "lock.fill", isOn: mode == .passcode) {
                withAnimation(.easeInOut(duration: 0.15)) { mode = .passcode }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { pinFocused = true }
            }
        }
        .padding(2)
        .background(Color.white.opacity(0.04))
        .clipShape(Capsule())
    }

    private func toggleButton(_ label: String, icon: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 10))
                Text(label).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2)
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(isOn ? Color(.sRGB, red: 0.40, green: 0.85, blue: 1.00, opacity: 0.18) : .clear)
            .foregroundColor(isOn ? Color(.sRGB, red: 0.40, green: 0.85, blue: 1.00, opacity: 1) : .white.opacity(0.6))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .face:
            NativeFaceCaptureView(
                baseURL: LumenAPIManager.shared.nexusBase,
                onAuthenticated: { cookie in
                    auth.handleSessionCookie(cookie)
                    withAnimation(.easeOut(duration: 0.2)) { presence.unlock() }
                }
            )
            .frame(height: 360)
        case .passcode:
            passcodePanel
        }
    }

    private var passcodePanel: some View {
        VStack(spacing: 14) {
            // Email pre-filled from last login — we know who you are, this
            // is just a re-verify, so we don't make you type it again.
            let email = UserDefaults.standard.string(forKey: "lumen.lastEmail") ?? ""
            HStack(spacing: 6) {
                Image(systemName: "person.fill").font(.system(size: 10)).foregroundColor(.white.opacity(0.4))
                Text(email.isEmpty ? "—" : email)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            SecureField("Passcode", text: $pin)
                .textFieldStyle(.plain)
                .focused($pinFocused)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.white)
                .onSubmit { Task { await submitPin() } }

            if !pinError.isEmpty {
                Text(pinError.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.5)
                    .foregroundColor(Color(.sRGB, red: 1.00, green: 0.42, blue: 0.42, opacity: 1))
            }

            Button(action: { Task { await submitPin() } }) {
                HStack(spacing: 8) {
                    if pinSubmitting {
                        ProgressView().controlSize(.small).tint(.black)
                    }
                    Text(pinSubmitting ? "VERIFYING…" : "UNLOCK")
                        .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(pin.isEmpty || pinSubmitting ? Color.white.opacity(0.18) : Color(.sRGB, red: 0.40, green: 0.85, blue: 1.00, opacity: 1))
                .foregroundColor(.black)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(pin.isEmpty || pinSubmitting)
        }
        .onAppear { pinFocused = true }
    }

    private var hint: some View {
        Text("App stays running. Sync, terminals, scheduled jobs continue underneath.")
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(.white.opacity(0.3))
            .multilineTextAlignment(.center)
    }

    // MARK: PIN submission

    private func submitPin() async {
        let trimmed = pin.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !pinSubmitting else { return }
        pinSubmitting = true
        pinError = ""
        defer { pinSubmitting = false }

        let base = LumenAPIManager.shared.nexusBase
        let email = UserDefaults.standard.string(forKey: "lumen.lastEmail") ?? ""
        guard let url = URL(string: "\(base)/api/security/pin"),
              !email.isEmpty else {
            pinError = "No remembered email — sign out and back in"
            return
        }

        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("1", forHTTPHeaderField: "X-Lumen-Client")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["email": email, "pin": trimmed])

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                pinError = "Network error"
                return
            }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if http.statusCode == 200,
               let sessionId = (json?["sessionId"] as? String) ?? extractCookie(from: http),
               !sessionId.isEmpty {
                auth.handleSessionCookie(sessionId)
                pin = ""
                withAnimation(.easeOut(duration: 0.2)) { presence.unlock() }
                return
            }
            pinError = http.statusCode == 401 ? "Incorrect passcode" : "Verification failed"
        } catch {
            pinError = "Connection error"
        }
    }

    private func extractCookie(from http: HTTPURLResponse) -> String? {
        guard let header = http.value(forHTTPHeaderField: "Set-Cookie") else { return nil }
        for part in header.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count == 2, kv[0] == "nx_session" { return kv[1] }
        }
        return nil
    }
}
