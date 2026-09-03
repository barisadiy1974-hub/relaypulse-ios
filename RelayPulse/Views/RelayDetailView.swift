import SwiftUI

struct RelayDetailView: View {
    @EnvironmentObject var fleet: FleetStore
    @EnvironmentObject var ai: AppSettings
    @Environment(\.colorScheme) private var scheme
    let server: Server
    @State private var showEdit = false
    @State private var diagnosing = false
    @State private var suggestion: AIFixer.Suggestion?
    @State private var output: ToolOutput?

    private var status: RelayStatus { fleet.status(for: server) }
    private var sc: Color { status.state.color(scheme) }
    private var needsHelp: Bool { status.state == .warn || status.state == .stale || status.state == .offline }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                PanelCard(stateColor: sc) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Circle().fill(sc).frame(width: 10, height: 10)
                            Text(status.state.label).font(.headline).foregroundStyle(sc)
                            Spacer()
                            Text(status.ageText + " ago").font(.caption).foregroundStyle(Theme.muted(scheme))
                        }
                        if status.fails > 0 {
                            Text("\(status.fails) consecutive failed polls")
                                .font(.caption).foregroundStyle(Theme.warn(scheme))
                        }
                        if let e = status.lastError {
                            Text(e).font(.caption).foregroundStyle(Theme.err(scheme))
                        }
                        if needsHelp {
                            Button {
                                Task { await diagnose() }
                            } label: {
                                HStack {
                                    Label(diagnosing ? "Diagnosing…" : "Diagnose with AI", systemImage: "sparkles")
                                    if diagnosing { Spacer(); ProgressView() }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(diagnosing)
                            .padding(.top, 4)
                        }
                    }
                }

                // Quick actions, same set as the desktop relay card.
                PanelCard {
                    HStack(spacing: 8) {
                        actionLink(.nyx, "Nyx")
                        actionLink(.log, "Log")
                        actionLink(.https, "HTTPS")
                        NavigationLink {
                            AnonrcEditorView(server: server)
                        } label: { actionLabel("Config", "slider.horizontal.3") }
                    }
                }

                infoCard("Metrics", [
                    ("anon service", status.anonLabel),
                    ("Connections", status.conn.map { "\($0)" } ?? "—"),
                    ("Download", mbps(status.rxMbps)),
                    ("Upload", mbps(status.txMbps)),
                    ("CPU", (status.cpuPct.map { "\(Int($0))%" } ?? pending) + (status.cpuCount.map { " · \($0) cores" } ?? "")),
                    ("RAM", status.memPct.map { "\(Int($0))%" } ?? "—"),
                    ("Disk", status.diskPct.map { "\(Int($0))%" } ?? "—"),
                    ("Load avg", status.load.map { l in l.count == 3 ? String(format: "%.2f  %.2f  %.2f", l[0], l[1], l[2]) : "—" } ?? "—"),
                    ("Uptime", status.uptime ?? "—"),
                ])

                infoCard("Server", [
                    ("Host", "\(server.host):\(server.agentPort)"),
                    ("Scheme", server.agentScheme.uppercased()),
                    ("Public IP", status.publicIp ?? "—"),
                    ("Wallet", server.wallet.isEmpty ? "—" : server.wallet),
                ])
            }
            .padding(12)
        }
        .background(Theme.bg(scheme))
        .navigationTitle(server.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") { showEdit = true }
            }
        }
        .sheet(isPresented: $showEdit) { ServerEditView(mode: .edit(server)) }
        .sheet(item: $output) { o in ToolOutputSheet(output: o) }
        .alert("AI diagnosis", isPresented: Binding(get: { suggestion != nil }, set: { if !$0 { suggestion = nil } })) {
            if let s = suggestion, let cmd = ai.commands.first(where: { $0.id == s.commandId }) {
                Button(ai.dryRun ? "Diagnosis only (dry-run on)" : "Run \"\(cmd.name)\"",
                       role: ai.dryRun ? .cancel : .destructive) {
                    if !ai.dryRun { Task { await run(cmd) } }
                    suggestion = nil
                }
                Button("Close", role: .cancel) { suggestion = nil }
            } else {
                Button("OK", role: .cancel) { suggestion = nil }
            }
        } message: {
            if let s = suggestion {
                Text(s.reason.isEmpty ? "The model did not suggest a command." : s.reason)
            }
        }
        .refreshable { await fleet.sweep() }
    }

    /// Rate metrics need two polls to produce a delta; say so instead of showing a bare dash.
    private var pending: String { status.lastUpdated == nil ? "—" : "calculating…" }

    /// Pulls recent logs over SSH, sends them to the model, shows the suggested
    /// command. Never runs anything on its own.
    private func diagnose() async {
        diagnosing = true
        defer { diagnosing = false }
        let errMsg = status.lastError ?? (status.anonHealthy ? "state: \(status.state.rawValue)" : "anon service \(status.anonLabel)")

        var logs = "(no logs)"
        do {
            let r = try await SSHRunner.shared.run(RelayScripts.log, on: server, timeout: 30)
            if !r.combined.isEmpty { logs = r.combined }
        } catch {
            AILog.shared.add(kind: .error, relay: server.name, title: "Could not fetch logs",
                             detail: error.localizedDescription, ok: false)
        }

        do {
            let s = try await AIFixer.analyze(server: server, errorMessage: errMsg, logs: logs,
                                              commands: ai.commands, provider: ai.aiProvider,
                                              key: ai.activeKey, workspaceId: ai.claudeWorkspaceId)
            let cmdName = ai.commands.first(where: { $0.id == s.commandId })?.name ?? "(no command suggested)"
            AILog.shared.add(kind: .analyze, relay: server.name, title: "Diagnosis: \(cmdName)",
                             detail: "Error: \(errMsg)\n\nReasoning: \(s.reason)", ok: true)
            suggestion = s
        } catch {
            AILog.shared.add(kind: .error, relay: server.name, title: "AI diagnosis failed",
                             detail: error.localizedDescription, ok: false)
            output = ToolOutput(title: "AI diagnosis", text: error.localizedDescription, failed: true)
        }
    }

    private func run(_ cmd: FixCommand) async {
        do {
            let r = try await SSHRunner.shared.run(cmd.command, on: server, timeout: 60)
            let ok = (r.exitStatus ?? 0) == 0
            let text = r.combined.isEmpty ? "(no output)" : r.combined
            AILog.shared.add(kind: .command, relay: server.name, title: cmd.name, detail: text, ok: ok)
            output = ToolOutput(title: cmd.name, text: text, failed: !ok)
        } catch {
            AILog.shared.add(kind: .error, relay: server.name, title: cmd.name,
                             detail: error.localizedDescription, ok: false)
            output = ToolOutput(title: cmd.name, text: error.localizedDescription, failed: true)
        }
    }

    private func actionLink(_ kind: ToolRunnerView.Kind, _ title: String) -> some View {
        NavigationLink {
            ToolRunnerView(kind: kind, fixedServer: server)
        } label: { actionLabel(title, kind.icon) }
    }

    private func actionLabel(_ title: String, _ icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 16))
            Text(title).font(.system(size: 10, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Theme.panel3(scheme))
        .foregroundStyle(Theme.accent(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func infoCard(_ title: String, _ rows: [(String, String)]) -> some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 0) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold)).tracking(0.5)
                    .foregroundStyle(Theme.muted(scheme))
                    .padding(.bottom, 6)
                ForEach(rows.indices, id: \.self) { i in
                    HStack {
                        Text(rows[i].0).foregroundStyle(Theme.muted(scheme))
                        Spacer()
                        Text(rows[i].1)
                            .foregroundStyle(Theme.text(scheme))
                            .multilineTextAlignment(.trailing)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .font(.system(size: 13))
                    .padding(.vertical, 5)
                    if i < rows.count - 1 { Divider().overlay(Theme.border(scheme)) }
                }
            }
        }
    }

    private func mbps(_ v: Double?) -> String {
        guard let v else { return pending }
        return String(format: v < 10 ? "%.2f Mbps" : "%.0f Mbps", v)
    }
}
