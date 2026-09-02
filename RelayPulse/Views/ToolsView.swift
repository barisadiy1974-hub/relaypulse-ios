import SwiftUI

/// Araçlar — Mac'teki Araçlar sekmesi + AI Auto-Fix ayarlarının iPhone karşılığı.
struct ToolsView: View {
    @EnvironmentObject var fleet: FleetStore
    @EnvironmentObject var ai: AppSettings
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        List {
            Section("Kurulum") {
                NavigationLink {
                    AISettingsView()
                } label: {
                    row("AI API anahtarı ve komutlar",
                        ai.hasKey ? "\(ai.aiProvider == "claude" ? "Claude" : "OpenAI") · anahtar var · \(ai.commands.count) komut"
                                  : "Anahtar girilmedi",
                        "key.horizontal",
                        ai.hasKey ? Theme.ok(scheme) : Theme.warn(scheme))
                }
                NavigationLink {
                    SSHSettingsView()
                } label: {
                    row("SSH anahtarı",
                        SSHKeyStore.hasKey ? "Yüklü — araçlar çalışır" : "Yok — nyx/htop/anonrc çalışmaz",
                        "terminal",
                        SSHKeyStore.hasKey ? Theme.ok(scheme) : Theme.warn(scheme))
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
                Text("Relay araçları")
            } footer: {
                Text("Bir relay seç: anonrc, nyx, htop, anon log, servis komutları.")
            }
        }
        .navigationTitle("Araçlar")
    }

    private func row(_ title: String, _ sub: String, _ icon: String, _ tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).foregroundStyle(Theme.text(scheme))
                Text(sub).font(.caption).foregroundStyle(Theme.muted(scheme))
            }
        }
    }
}

