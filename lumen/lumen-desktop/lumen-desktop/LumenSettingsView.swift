import SwiftUI
import AppKit

// LumenSettingsView
//
// Settings tab for the Console. Surfaces:
//   - Active human (display name, email, role, auth method, last verified)
//   - Sync cadence overrides (UserDefaults-backed, runtime-applied)
//   - Host override (auto / force-local / force-remote)
//   - Sign out
//   - Open native macOS System Settings → Lumen for permissions
//
// Lives in the Console window (Cmd-Opt-D → Settings tab) so power-user
// controls don't clutter the main MainView. Patrick can swap the in-MainView
// SettingsPanel to a thin link to this if he wants.

struct LumenSettingsView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var authRegistry: LumenAuthRegistry

    // UserDefaults-backed prefs
    @AppStorage("lumen.host.mode")          private var hostMode: String   = "auto"  // auto | local | remote
    @AppStorage("lumen.cadence.dashboard")  private var cadenceDashboard: Double = 20
    @AppStorage("lumen.cadence.conv")       private var cadenceConv: Double      = 45
    @AppStorage("lumen.cadence.mid")        private var cadenceMid: Double       = 90
    @AppStorage("lumen.cadence.localdb")    private var cadenceLocalDB: Double   = 300

    @State private var signingOut = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                identitySection
                Divider().background(Color.white.opacity(0.06))
                hostSection
                Divider().background(Color.white.opacity(0.06))
                cadenceSection
                Divider().background(Color.white.opacity(0.06))
                actionsSection
            }
            .padding(24)
        }
    }

    // MARK: - Identity

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("ACTIVE HUMAN")
            if let active = authRegistry.activeHuman {
                VStack(alignment: .leading, spacing: 6) {
                    fieldRow("Name", active.displayName)
                    fieldRow("Email", active.email)
                    fieldRow("Role", active.role.uppercased())
                    if active.isOwner {
                        Text("OWNER")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1.5)
                            .foregroundColor(Color.cyanAccent)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.cyanAccent.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4).stroke(Color.cyanAccent.opacity(0.4), lineWidth: 1)
                            )
                    }
                }
                .padding(14)
                .background(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
            } else {
                Text("Not signed in")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.45))
            }
        }
    }

    // MARK: - Host

    private var hostSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("API HOST")
            Text("Which Nexus backend Lumen talks to. \"Auto\" probes localhost first, falls back to production. Override when you want to pin behavior during testing.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.55))
            Picker("", selection: $hostMode) {
                Text("AUTO").tag("auto")
                Text("FORCE LOCAL").tag("local")
                Text("FORCE REMOTE").tag("remote")
            }
            .pickerStyle(.segmented)
            .onChange(of: hostMode) { _, _ in
                Task { await LumenAPIManager.shared.resolveBaseURL() }
            }
            Text("CURRENTLY: \(currentHostLabel)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(.white.opacity(0.5))
        }
    }

    private var currentHostLabel: String {
        let base = LumenAPIManager.shared.nexusBase
        if base.contains("localhost") { return "LOCAL DEV (localhost:3000)" }
        if let h = URL(string: base)?.host { return h.uppercased() }
        return base
    }

    // MARK: - Cadences

    private var cadenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("SYNC CADENCES")
            Text("How often Lumen polls each surface. Lower = fresher data + more battery. Manual \"Sync now\" always works regardless of cadence.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.55))

            cadenceRow("Dashboard",   value: $cadenceDashboard, range: 10...120, unit: "s")
            cadenceRow("Conversations", value: $cadenceConv,    range: 30...300, unit: "s")
            cadenceRow("Directives + memory", value: $cadenceMid, range: 60...600, unit: "s")
            cadenceRow("Local DB delta",  value: $cadenceLocalDB, range: 120...1800, unit: "s")

            Button("RESET TO DEFAULTS") {
                cadenceDashboard = 20
                cadenceConv = 45
                cadenceMid = 90
                cadenceLocalDB = 300
            }
            .buttonStyle(.plain)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(2)
            .foregroundColor(.white.opacity(0.5))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .overlay(
                RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
        }
    }

    private func cadenceRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Text("\(Int(value.wrappedValue))\(unit)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color.cyanAccent)
            }
            Slider(value: value, in: range, step: 5)
                .accentColor(Color.cyanAccent)
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("ACTIONS")
            HStack(spacing: 10) {
                Button(action: openSystemSettings) {
                    HStack(spacing: 6) {
                        Image(systemName: "gear").font(.system(size: 11, weight: .bold))
                        Text("MACOS SETTINGS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(2)
                    }
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help("Opens System Settings → Lumen for camera, mic, notification permissions.")

                Button(action: signOut) {
                    HStack(spacing: 6) {
                        if signingOut {
                            ProgressView().controlSize(.small).tint(Color.redAccent)
                        } else {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                        Text(signingOut ? "SIGNING OUT" : "SIGN OUT")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(2)
                    }
                    .foregroundColor(Color.redAccent)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6).fill(Color.redAccent.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6).stroke(Color.redAccent.opacity(0.4), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(signingOut)

                Spacer()
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .tracking(3)
            .foregroundColor(Color.cyanAccent.opacity(0.95))
    }

    private func fieldRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.45))
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.85))
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func openSystemSettings() {
        // Deep link to System Settings → app-specific privacy
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }

    private func signOut() {
        signingOut = true
        Task {
            await auth.signOut()
            await MainActor.run { signingOut = false }
        }
    }
}

private extension Color {
    static let cyanAccent  = Color(.sRGB, red: 0.40, green: 0.85, blue: 1.00, opacity: 1)
    static let greenAccent = Color(.sRGB, red: 0.30, green: 0.92, blue: 0.55, opacity: 1)
    static let redAccent   = Color(.sRGB, red: 1.00, green: 0.42, blue: 0.42, opacity: 1)
}
