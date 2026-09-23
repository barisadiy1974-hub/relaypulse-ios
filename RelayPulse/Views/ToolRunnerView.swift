import SwiftUI

/// One tool (Nyx / htop / log / HTTPS) with a server picker, a run button and
/// its output — the phone equivalent of the desktop Tools tabs.
struct ToolRunnerView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case nyx, htop, log, https
        var id: String { rawValue }

        var title: String {
            switch self {
            case .nyx:   return "Nyx"
            case .htop:  return "htop"
            case .log:   return "Service log"
            case .https: return "HTTPS agent check"
            }
        }
        var subtitle: String {
            switch self {
            case .nyx:   return "Version, uptime, traffic, consensus flags, weight, connections"
            case .htop:  return "Load, top CPU/memory processes, disk"
            case .log:   return "journalctl for the watched service"
            case .https: return "Is the agent on :19191 reachable"
            }
        }
        var icon: String {
            switch self {
            case .nyx:   return "chart.xyaxis.line"
            case .htop:  return "cpu"
            case .log:   return "doc.text.magnifyingglass"
            case .https: return "lock.shield"
            }
        }
        /// nyx and htop are full-screen curses programs; these are one-shot
        /// equivalents. Nyx talks to anon's control socket for the real data.
        var command: String {
            switch self {
            case .nyx:   return RelayScripts.nyx
            case .htop:  return RelayScripts.htop
            case .log:   return RelayScripts.log
            case .https: return RelayScripts.https
            }
        }
    }

    @EnvironmentObject var fleet: FleetStore
    @Environment(\.colorScheme) private var scheme
    let kind: Kind
    /// When opened for a specific relay the picker is hidden.
    var fixedServer: Server? = nil

    @State private var selected: String = ""
    @State private var running = false
    @State private var output: ToolOutput?

    private var server: Server? {
        fixedServer ?? fleet.servers.first { $0.name == selected } ?? fleet.servers.first
    }

    var body: some View {
        Form {
            if fixedServer == nil {
                Section("Server") {
                    Picker("Server", selection: $selected) {
                        ForEach(fleet.servers) { s in Text(s.name).tag(s.name) }
                    }
                }
            }

            Section {
                Button {
                    Task { await run() }
                } label: {
                    HStack {
                        Label(running ? "Running…" : "Run", systemImage: kind.icon)
                        if running { Spacer(); ProgressView() }
                    }
                }
                .disabled(running || server == nil)
            } footer: {
                Text(kind.subtitle)
            }

            if !SSHKeyStore.hasKey {
                Section {
                    Label("No SSH key — add one in Tools › SSH key", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.warn(scheme))
                        .font(.footnote)
                }
            }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $output) { o in ToolOutputSheet(output: o) }
        .onAppear { if selected.isEmpty { selected = fleet.servers.first?.name ?? "" } }
    }

    private func run() async {
        guard let s = server else { return }
        running = true
        defer { running = false }
        do {
            let r = try await SSHRunner.shared.run(kind.command, on: s, timeout: 40)
            let ok = (r.exitStatus ?? 0) == 0
            let text = r.combined.isEmpty ? "(no output)" : r.combined
            output = ToolOutput(title: "\(kind.title) · \(s.name)", text: text, failed: !ok)
            AILog.shared.add(kind: .command, relay: s.name, title: kind.title, detail: text, ok: ok)
        } catch {
            output = ToolOutput(title: "\(kind.title) · \(s.name)", text: error.localizedDescription, failed: true)
            AILog.shared.add(kind: .error, relay: s.name, title: kind.title,
                             detail: error.localizedDescription, ok: false)
        }
    }
}

/// Server picker for the anonrc editor — the desktop config tab's equivalent.
struct AnonrcPickerView: View {
    @EnvironmentObject var fleet: FleetStore
    @State private var selected: String = ""

    var body: some View {
        Form {
            Section("Server") {
                Picker("Server", selection: $selected) {
                    ForEach(fleet.servers) { s in Text(s.name).tag(s.name) }
                }
            }
            if let s = fleet.servers.first(where: { $0.name == selected }) {
                Section {
                    NavigationLink {
                        AnonrcEditorView(server: s)
                    } label: {
                        Label("Open anonrc", systemImage: "slider.horizontal.3")
                    }
                } footer: {
                    Text("Read over SSH. Saving takes a timestamped backup first, then asks whether to restart the anon service.")
                }
            }
        }
        .navigationTitle("Config (anonrc)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if selected.isEmpty { selected = fleet.servers.first?.name ?? "" } }
    }
}
