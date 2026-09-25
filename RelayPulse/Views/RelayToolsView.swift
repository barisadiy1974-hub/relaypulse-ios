import SwiftUI

/// All tools for a single relay — Tools › Per relay.
/// Commands live in `RelayScripts`; this screen just pins them to one server.
struct RelayToolsView: View {
    @EnvironmentObject var ai: AppSettings
    @Environment(\.colorScheme) private var scheme
    let server: Server

    @State private var running: Int?
    @State private var output: ToolOutput?
    /// Tapped but not yet confirmed. These run as root on a live relay, and a
    /// stray tap while scrolling this list would have restarted the anon
    /// service outright — RelayDetailView already puts the same commands behind
    /// a confirmation, so this matches it.
    @State private var pending: FixCommand?

    var body: some View {
        List {
            Section("Monitoring") {
                ForEach(ToolRunnerView.Kind.allCases) { k in
                    NavigationLink {
                        ToolRunnerView(kind: k, fixedServer: server)
                    } label: {
                        label(k.title, k.subtitle, k.icon)
                    }
                }
            }

            Section("Configuration") {
                NavigationLink {
                    AnonrcEditorView(server: server)
                } label: {
                    label("Edit anonrc", "Read and write /etc/anon/anonrc", "slider.horizontal.3")
                }
            }

            Section {
                ForEach(ai.commands) { c in
                    Button {
                        pending = c
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "terminal").foregroundStyle(Theme.muted(scheme)).frame(width: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(c.name).foregroundStyle(Theme.text(scheme))
                                Text(c.command).font(.caption2.monospaced())
                                    .foregroundStyle(Theme.muted(scheme)).lineLimit(1)
                            }
                            Spacer()
                            if running == c.id { ProgressView() }
                            else { Image(systemName: "play.circle").foregroundStyle(Theme.accent(scheme)) }
                        }
                    }
                    .disabled(running != nil)
                }
            } header: {
                Text("Fix commands")
            } footer: {
                Text("Runs as root on the relay. Same list as desktop RelayPulse.")
            }
        }
        .navigationTitle(server.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $output) { o in ToolOutputSheet(output: o) }
        .confirmationDialog(pending.map { "Run \"\($0.name)\" on \(server.name)?" } ?? "",
                            isPresented: Binding(get: { pending != nil },
                                                 set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible) {
            if let c = pending {
                Button("Run as root", role: .destructive) { run(c); pending = nil }
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            if let c = pending { Text(c.command) }
        }
    }

    private func label(_ title: String, _ sub: String, _ icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Theme.muted(scheme)).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).foregroundStyle(Theme.text(scheme))
                Text(sub).font(.caption).foregroundStyle(Theme.muted(scheme)).lineLimit(2)
            }
        }
    }

    private func run(_ c: FixCommand) {
        running = c.id
        Task {
            do {
                let r = try await SSHRunner.shared.run(c.script, on: server, timeout: 60)
                let ok = (r.exitStatus ?? 0) == 0
                let text = r.combined.isEmpty ? "(no output)" : r.combined
                output = ToolOutput(title: c.name, text: text, failed: !ok)
                AILog.shared.add(kind: .command, relay: server.name, title: c.name, detail: text, ok: ok)
            } catch {
                output = ToolOutput(title: c.name, text: error.localizedDescription, failed: true)
                AILog.shared.add(kind: .error, relay: server.name, title: c.name,
                                 detail: error.localizedDescription, ok: false)
            }
            running = nil
        }
    }
}
