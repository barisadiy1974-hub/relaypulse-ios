import SwiftUI

/// Mac'teki Araçlar sekmelerinin (Nyx / htop / Log / HTTPS) karşılığı:
/// sunucu seçicisi + çalıştır + çıktı. Her araç kendi komutunu taşır.
struct ToolRunnerView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case nyx, htop, log, https
        var id: String { rawValue }

        var title: String {
            switch self {
            case .nyx:   return "Nyx"
            case .htop:  return "htop"
            case .log:   return "anon log"
            case .https: return "HTTPS agent testi"
            }
        }
        var subtitle: String {
            switch self {
            case .nyx:   return "Sürüm, uptime, trafik, consensus bayrakları, ağırlık, bağlantılar"
            case .htop:  return "Yük, en çok CPU/bellek kullanan süreçler, disk"
            case .log:   return "journalctl -u anon -n 60"
            case .https: return "Agent :19191 erişilebilir mi"
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
        /// nyx/htop tam ekran curses uygulamaları — telefonda tek seferlik eşdeğerleri.
        /// nyx, anon'un kontrol soketine bağlanıp gerçek relay verisini çeker.
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
    /// Belirli bir relay için açıldıysa seçici gizlenir.
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
                Section("Sunucu") {
                    Picker("Relay", selection: $selected) {
                        ForEach(fleet.servers) { s in Text(s.name).tag(s.name) }
                    }
                }
            }

            Section {
                Button {
                    Task { await run() }
                } label: {
                    HStack {
                        Label(running ? "Çalışıyor…" : "Çalıştır", systemImage: kind.icon)
                        if running { Spacer(); ProgressView() }
                    }
                }
                .disabled(running || server == nil)
            } footer: {
                Text(kind.subtitle)
            }

            if !SSHKeyStore.hasKey {
                Section {
                    Label("SSH anahtarı yok — Araçlar › SSH anahtarı'ndan ekle", systemImage: "exclamationmark.triangle")
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
            let text = r.combined.isEmpty ? "(çıktı yok)" : r.combined
            output = ToolOutput(title: "\(kind.title) · \(s.name)", text: text, failed: !ok)
            AILog.shared.add(kind: .command, relay: s.name, title: kind.title, detail: text, ok: ok)
        } catch {
            output = ToolOutput(title: "\(kind.title) · \(s.name)", text: error.localizedDescription, failed: true)
            AILog.shared.add(kind: .error, relay: s.name, title: kind.title,
                             detail: error.localizedDescription, ok: false)
        }
    }
}

/// Config (anonrc) için sunucu seçici — Mac'teki config sekmesinin karşılığı.
struct AnonrcPickerView: View {
    @EnvironmentObject var fleet: FleetStore
    @State private var selected: String = ""

    var body: some View {
        Form {
            Section("Sunucu") {
                Picker("Relay", selection: $selected) {
                    ForEach(fleet.servers) { s in Text(s.name).tag(s.name) }
                }
            }
            if let s = fleet.servers.first(where: { $0.name == selected }) {
                Section {
                    NavigationLink {
                        AnonrcEditorView(server: s)
                    } label: {
                        Label("anonrc'yi aç", systemImage: "slider.horizontal.3")
                    }
                } footer: {
                    Text("Dosya SSH ile okunur. Kaydederken önce zaman damgalı yedek alınır, sonra anon servisini yeniden başlatmayı sorar.")
                }
            }
        }
        .navigationTitle("Config (anonrc)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if selected.isEmpty { selected = fleet.servers.first?.name ?? "" } }
    }
}
