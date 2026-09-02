import SwiftUI

/// Tek relay için araçlar — Mac'teki nyx / htop / anon log / anonrc karşılığı.
/// nyx ve htop tam ekran curses uygulamaları; telefonda tek seferlik (batch)
/// eşdeğerleri çalıştırılır — aynı bilgi, interaktif ekran olmadan.
struct RelayToolsView: View {
    @EnvironmentObject var ai: AppSettings
    @Environment(\.colorScheme) private var scheme
    let server: Server

    @State private var running: String?
    @State private var output: ToolOutput?

    private struct Tool: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let command: String
    }

    private var systemTools: [Tool] { [
        .init(id: "nyx", title: "Relay durumu", subtitle: "nyx yerine: servis + bayraklar + bağlantı",
              icon: "chart.xyaxis.line",
              command: """
              for svc in anon anon@default anyone anyone-relay; do systemctl is-active "$svc" >/dev/null 2>&1 && systemctl status "$svc" --no-pager -n 0 | head -6 && break; done
              echo '--- dinlenen portlar ---'; ss -tnlp 2>/dev/null | grep -E ':(9001|9030|9050|9051)' || echo '(yok)'
              echo '--- baglanti ---'; ss -tn state established 2>/dev/null | tail -n +2 | wc -l
              echo '--- fingerprint ---'; cat /var/lib/anon/fingerprint 2>/dev/null || find /var/lib/anon* -name fingerprint -exec cat {} \\; 2>/dev/null | head -2 || echo '(yok)'
              """),
        .init(id: "htop", title: "Süreçler ve yük", subtitle: "htop yerine: top -bn1 + bellek",
              icon: "cpu",
              command: "top -bn1 2>/dev/null | head -20; echo '--- bellek ---'; free -m 2>/dev/null; echo '--- disk ---'; df -h / 2>/dev/null"),
        .init(id: "log", title: "anon log", subtitle: "journalctl -u anon -n 60",
              icon: "doc.text.magnifyingglass",
              command: "journalctl -u anon -n 60 --no-pager 2>/dev/null || journalctl -u anyone-relay -n 60 --no-pager 2>/dev/null || echo '(log bulunamadi)'"),
    ] }

    var body: some View {
        List {
            Section("İzleme") {
                ForEach(systemTools) { t in toolRow(t) }
            }

            Section("Yapılandırma") {
                NavigationLink {
                    AnonrcEditorView(server: server)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "slider.horizontal.3").foregroundStyle(Theme.muted(scheme)).frame(width: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("anonrc düzenle").foregroundStyle(Theme.text(scheme))
                            Text("/etc/anon/anonrc oku ve yaz").font(.caption).foregroundStyle(Theme.muted(scheme))
                        }
                    }
                }
            }

            Section {
                ForEach(ai.commands) { c in
                    toolRow(.init(id: "cmd\(c.id)", title: c.name, subtitle: c.command,
                                  icon: "terminal", command: c.command), mono: true)
                }
            } header: {
                Text("Düzeltme komutları")
            } footer: {
                Text("Bu komutlar relay'de root olarak çalışır. Mac RelayPulse'taki liste ile aynı.")
            }
        }
        .navigationTitle(server.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $output) { o in ToolOutputSheet(output: o) }
    }

    private func toolRow(_ t: Tool, mono: Bool = false) -> some View {
        Button {
            run(t)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: t.icon).foregroundStyle(Theme.muted(scheme)).frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.title).foregroundStyle(Theme.text(scheme))
                    Text(t.subtitle)
                        .font(mono ? .caption2.monospaced() : .caption)
                        .foregroundStyle(Theme.muted(scheme)).lineLimit(1)
                }
                Spacer()
                if running == t.id { ProgressView() }
                else { Image(systemName: "play.circle").foregroundStyle(Theme.accent(scheme)) }
            }
        }
        .disabled(running != nil)
    }

    private func run(_ t: Tool) {
        running = t.id
        Task {
            do {
                let r = try await SSHRunner.shared.run(t.command, on: server, timeout: 30)
                output = ToolOutput(title: t.title, text: r.combined.isEmpty ? "(çıktı yok)" : r.combined,
                                    failed: (r.exitStatus ?? 0) != 0)
            } catch {
                output = ToolOutput(title: t.title, text: error.localizedDescription, failed: true)
            }
            running = nil
        }
    }
}

struct ToolOutput: Identifiable {
    let id = UUID()
    let title: String
    let text: String
    let failed: Bool
}

struct ToolOutputSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    let output: ToolOutput

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(output.text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(output.failed ? Theme.err(scheme) : Theme.text(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .background(Theme.bg(scheme))
            .navigationTitle(output.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Kapat") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: output.text) { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
    }
}
