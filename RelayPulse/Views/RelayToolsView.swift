import SwiftUI

/// Tek relay için tüm araçlar bir arada — Araçlar › Relay başına.
/// Komutlar `RelayScripts`'te; burada sadece o relay'e sabitlenmiş bağlantılar var.
struct RelayToolsView: View {
    @EnvironmentObject var ai: AppSettings
    @Environment(\.colorScheme) private var scheme
    let server: Server

    @State private var running: Int?
    @State private var output: ToolOutput?

    var body: some View {
        List {
            Section("İzleme") {
                ForEach(ToolRunnerView.Kind.allCases) { k in
                    NavigationLink {
                        ToolRunnerView(kind: k, fixedServer: server)
                    } label: {
                        label(k.title, k.subtitle, k.icon)
                    }
                }
            }

            Section("Yapılandırma") {
                NavigationLink {
                    AnonrcEditorView(server: server)
                } label: {
                    label("anonrc düzenle", "/etc/anon/anonrc oku ve yaz", "slider.horizontal.3")
                }
            }

            Section {
                ForEach(ai.commands) { c in
                    Button {
                        run(c)
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
                Text("Düzeltme komutları")
            } footer: {
                Text("Relay'de root olarak çalışır. Mac RelayPulse'taki liste ile aynı.")
            }
        }
        .navigationTitle(server.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $output) { o in ToolOutputSheet(output: o) }
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
                let r = try await SSHRunner.shared.run(c.command, on: server, timeout: 60)
                let ok = (r.exitStatus ?? 0) == 0
                let text = r.combined.isEmpty ? "(çıktı yok)" : r.combined
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
