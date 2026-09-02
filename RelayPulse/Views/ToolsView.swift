import SwiftUI

/// Araçlar — Mac RelayPulse'un Araçlar sekmesiyle aynı yapı:
/// Nyx / htop / Log / HTTPS / Config her biri kendi sunucu seçicisiyle, ayrı.
struct ToolsView: View {
    @EnvironmentObject var fleet: FleetStore
    @EnvironmentObject var ai: AppSettings
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        List {
            Section("Araçlar") {
                ForEach(ToolRunnerView.Kind.allCases) { k in
                    NavigationLink {
                        ToolRunnerView(kind: k)
                    } label: {
                        row(k.title, k.subtitle, k.icon, Theme.accent(scheme))
                    }
                }
                NavigationLink {
                    AnonrcPickerView()
                } label: {
                    row("Config (anonrc)", "Relay yapılandırmasını oku ve yaz",
                        "slider.horizontal.3", Theme.accent(scheme))
                }
            }

            Section("Kurulum") {
                NavigationLink {
                    AISettingsView()
                } label: {
                    row("AI API anahtarı ve komutlar",
                        ai.hasKey ? "\(ai.providerLabel) · anahtar var · \(ai.commands.count) komut"
                                  : "\(ai.providerLabel) anahtarı girilmedi",
                        "key.horizontal",
                        ai.hasKey ? Theme.ok(scheme) : Theme.warn(scheme))
                }
                NavigationLink {
                    SSHSettingsView()
                } label: {
                    row("SSH anahtarı",
                        SSHKeyStore.hasKey ? "Yüklü — araçlar çalışır" : "Yok — araçlar çalışmaz",
                        "terminal",
                        SSHKeyStore.hasKey ? Theme.ok(scheme) : Theme.warn(scheme))
                }
                NavigationLink {
                    AILogView()
                } label: {
                    row("AI kaydı / hatalar", "Teşhisler, çalıştırılan komutlar, hatalar",
                        "list.bullet.rectangle", Theme.muted(scheme))
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
                Text("Relay başına")
            } footer: {
                Text("Tek relay için tüm araçlar + düzeltme komutları bir arada.")
            }
        }
        .navigationTitle("Araçlar")
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
