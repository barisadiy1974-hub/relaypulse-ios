import SwiftUI

/// Tools — mirrors the desktop RelayPulse Tools tab: Nyx / htop / log / HTTPS /
/// config, each with its own server picker.
struct ToolsView: View {
    @EnvironmentObject var fleet: FleetStore
    @EnvironmentObject var ai: AppSettings
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        List {
            Section("Tools") {
                ForEach(ToolRunnerView.Kind.allCases.filter { $0 != .nyx || fleet.hasRelays }) { k in
                    NavigationLink {
                        ToolRunnerView(kind: k)
                    } label: {
                        row(k.title, k.subtitle, k.icon, Theme.accent(scheme))
                    }
                }
                if fleet.hasRelays {
                    NavigationLink {
                        AnonrcPickerView()
                    } label: {
                        row("Config (anonrc)", "Read and write the relay configuration",
                            "slider.horizontal.3", Theme.accent(scheme))
                    }
                }
            }

            Section("Setup") {
                NavigationLink {
                    AISettingsView()
                } label: {
                    row("AI API key and commands",
                        ai.hasKey ? "\(ai.providerLabel) · key set · \(ai.commands.count) commands"
                                  : "No \(ai.providerLabel) key yet",
                        "key.horizontal",
                        ai.hasKey ? Theme.ok(scheme) : Theme.warn(scheme))
                }
                NavigationLink {
                    SSHSettingsView()
                } label: {
                    row("SSH key",
                        SSHKeyStore.hasKey ? "Loaded — tools work" : "Not set — servers log in with their password",
                        "terminal",
                        SSHKeyStore.hasKey ? Theme.ok(scheme) : Theme.warn(scheme))
                }
                NavigationLink {
                    AILogView()
                } label: {
                    row("Activity log / errors", "Diagnoses, commands that ran, errors",
                        "list.bullet.rectangle", Theme.muted(scheme))
                }
                NavigationLink {
                    HelpView()
                } label: {
                    row("Help", "Making an SSH key, what the colours mean, why a server will not connect",
                        "questionmark.circle", Theme.accent(scheme))
                }
            }

            Section {
                ForEach(fleet.servers) { s in
                    NavigationLink {
                        RelayToolsView(server: s)
                    } label: {
                        HStack(spacing: 10) {
                            Circle().fill(fleet.status(for: s).state.color(scheme)).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.name).foregroundStyle(Theme.text(scheme))
                                Text(s.host).font(.caption).foregroundStyle(Theme.muted(scheme))
                            }
                        }
                    }
                }
            } header: {
                Text("Per server")
            } footer: {
                Text("Every tool plus the fix commands, scoped to one server.")
            }
        }
        .navigationTitle("Tools")
    }

    private func row(_ title: String, _ sub: String, _ icon: String, _ tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).foregroundStyle(Theme.text(scheme))
                Text(sub).font(.caption).foregroundStyle(Theme.muted(scheme)).lineLimit(2)
            }
        }
    }
}
