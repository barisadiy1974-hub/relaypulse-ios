import SwiftUI

/// Araçlar — Mac'teki Araçlar sekmesi + AI Auto-Fix ayarlarının iPhone karşılığı.
struct ToolsView: View {
    @EnvironmentObject var fleet: FleetStore
    @EnvironmentObject var ai: AppSettings
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        List {
            Section("AI / Auto-Fix") {
                NavigationLink {
                    AISettingsView()
                } label: {
                    row("AI API anahtarı ve komutlar",
                        ai.hasKey ? "\(ai.aiProvider == "claude" ? "Claude" : "OpenAI") · anahtar var · \(ai.commands.count) komut"
                                  : "Anahtar girilmedi",
                        "key.horizontal",
                        ai.hasKey ? Theme.ok(scheme) : Theme.warn(scheme))
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

/// Tek bir relay için araçlar — Mac'teki kart butonlarının (nyx / log / htop / anonrc) karşılığı.
struct RelayToolsView: View {
    @EnvironmentObject var ai: AppSettings
    @Environment(\.colorScheme) private var scheme
    let server: Server

    var body: some View {
        List {
            Section("Terminal") {
                toolRow("nyx", "Anon relay izleyici (curses)", "chart.xyaxis.line")
                toolRow("htop", "Süreç izleyici", "cpu")
                toolRow("anon log", "journalctl -u anon -f", "doc.text.magnifyingglass")
            }

            Section("Yapılandırma") {
                toolRow("anonrc düzenle", "/etc/anon/anonrc oku ve yaz", "slider.horizontal.3")
            }

            Section("Komutlar") {
                ForEach(ai.commands) { c in
                    toolRow(c.name, c.command, "terminal", mono: true)
                }
            }
        }
        .navigationTitle(server.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Text("SSH bağlantısı ekleniyor — anahtar aktarımı onayını bekliyor.")
                .font(.caption)
                .foregroundStyle(Theme.muted(scheme))
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(.bar)
        }
    }

    private func toolRow(_ title: String, _ sub: String, _ icon: String, mono: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Theme.muted(scheme)).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).foregroundStyle(Theme.text(scheme))
                Text(sub)
                    .font(mono ? .caption2.monospaced() : .caption)
                    .foregroundStyle(Theme.muted(scheme))
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "lock").font(.caption2).foregroundStyle(.tertiary)
        }
    }
}
