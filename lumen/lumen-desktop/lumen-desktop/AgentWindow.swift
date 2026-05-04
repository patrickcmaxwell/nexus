// AgentWindow.swift
//
// Native window for a single Agent. Opens via
//   openWindow(id: "agent-detail", value: agentId)
// Mirrors OperationWindow's pattern — full-page detail, refresh button,
// reuses AgentDetailCard so it stays in sync with the panel view.

import SwiftUI

struct AgentWindow: View {
    let agentId: String
    @EnvironmentObject var store: LumenStore
    @State private var loading = true
    @State private var scanning = false
    @State private var toggling = false

    private var agent: AgentStatus? {
        store.agents.first { $0.agentId == agentId }
    }

    var body: some View {
        ZStack {
            BackgroundLayer()
            if let agent {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(for: agent)
                        AgentDetailCard(
                            agent: agent,
                            details: store.agentRecords[agent.agentId] ?? [:],
                            activity: store.activityByAgent[agent.agentId] ?? [],
                            chat: store.agentChats[agent.agentId] ?? [],
                            isSendingChat: store.agentChatSending == agent.agentId,
                            isScanning: scanning,
                            isToggling: toggling,
                            onRunScan: { runScan(for: agent) },
                            onToggle: { toggle(agent: agent) },
                            onSendChat: { msg in Task { await store.sendAgentChat(agentId: agent.agentId, message: msg) } },
                            onClearChat: { store.clearAgentChat(agentId: agent.agentId) }
                        )
                    }
                    .padding(24)
                }
            } else {
                VStack(spacing: 12) {
                    if loading {
                        ProgressView().controlSize(.large).tint(C.eve)
                        Text("Loading agent…")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("Agent not found")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.primary.opacity(0.7))
                        Text(agentId)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await refresh() }
    }

    private func header(for agent: AgentStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 14))
                    .foregroundColor(C.listen)
                Text("AGENT")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(4)
                    .foregroundColor(.secondary)
                Spacer()
                if loading {
                    ProgressView().controlSize(.mini).tint(C.eve)
                }
                Button(action: { Task { await refresh() } }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 9, weight: .bold))
                        Text("REFRESH").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.5)
                    }
                    .foregroundColor(C.listen)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(C.listen.opacity(0.12))
                    .overlay(Capsule().strokeBorder(C.listen.opacity(0.4), lineWidth: 1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Text(agent.name)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundColor(.primary.opacity(0.95))
            Text(agent.role)
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                StatusBadge(label: agent.status.uppercased(), color: agent.status == "active" ? C.listen : C.eve)
                StatusBadge(label: "\(agent.totalFindings) FINDINGS", color: C.think)
            }
            Text(agent.agentId)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.7))
                .textSelection(.enabled)
        }
    }

    private func refresh() async {
        loading = true
        defer { loading = false }
        if store.agents.isEmpty { await store.fetchDashboard() }
        await store.fetchAgentActivity(id: agentId)
    }

    private func runScan(for agent: AgentStatus) {
        scanning = true
        Task {
            await LumenAPIManager.shared.runAgent(id: agent.agentId)
            await store.fetchDashboard()
            await store.fetchAgentActivity(id: agent.agentId)
            scanning = false
        }
    }

    private func toggle(agent: AgentStatus) {
        toggling = true
        let newStatus = agent.status == "active" ? "standby" : "active"
        Task {
            await LumenAPIManager.shared.setAgentStatus(id: agent.agentId, status: newStatus)
            await store.fetchDashboard()
            await store.fetchAgentActivity(id: agent.agentId)
            toggling = false
        }
    }
}

private struct StatusBadge: View {
    let label: String
    let color: Color
    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(1.5)
            .foregroundColor(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.12))
            .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 1))
            .clipShape(Capsule())
    }
}
