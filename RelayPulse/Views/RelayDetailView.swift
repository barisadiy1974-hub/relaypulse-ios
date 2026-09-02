import SwiftUI

struct RelayDetailView: View {
    let server: Server
    @EnvironmentObject var fleet: FleetStore

    private var status: RelayStatus { fleet.status(for: server) }

    var body: some View {
        List {
            Section("Durum") {
                row("Durum") {
                    HStack(spacing: 6) {
                        Circle().fill(status.state.color).frame(width: 9, height: 9)
                        Text(status.state.label).foregroundStyle(status.state.color)
                    }
                }
                row("anon servisi") { Text(status.anonLabel) }
                if status.fails > 0 { row("Ardışık hata") { Text("\(status.fails)") } }
                if let e = status.lastError { row("Son hata") { Text(e).foregroundStyle(.red) } }
                row("Güncelleme") { Text(status.ageText + " önce") }
            }

            Section("Metrikler") {
                row("Bağlantı") { Text(status.conn.map { "\($0)" } ?? "—") }
                row("İndirme") { Text(mbps(status.rxMbps)) }
                row("Yükleme") { Text(mbps(status.txMbps)) }
                row("CPU") { Text(status.cpuPct.map { "\(Int($0))%" } ?? "—") + Text(status.cpuCount.map { " (\($0) çekirdek)" } ?? "") }
                row("RAM") { Text(status.memPct.map { "\(Int($0))%" } ?? "—") }
                row("Disk") { Text(status.diskPct.map { "\(Int($0))%" } ?? "—") }
                if let l = status.load, l.count == 3 {
                    row("Yük ort.") { Text(String(format: "%.2f  %.2f  %.2f", l[0], l[1], l[2])) }
                }
                row("Uptime") { Text(status.uptime ?? "—") }
            }

            Section("Sunucu") {
                row("Host") { Text("\(server.host):\(server.agentPort)") }
                row("Şema") { Text(server.agentScheme.uppercased()) }
                row("Public IP") { Text(status.publicIp ?? "—") }
                if !server.wallet.isEmpty {
                    row("Cüzdan") { Text(server.wallet).font(.caption).lineLimit(1).truncationMode(.middle) }
                }
            }
        }
        .navigationTitle(server.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await fleet.sweep() }
    }

    private func row<V: View>(_ label: String, @ViewBuilder _ value: () -> V) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            value().multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }

    private func mbps(_ v: Double?) -> String {
        guard let v else { return "—" }
        return String(format: v < 10 ? "%.2f Mbps" : "%.0f Mbps", v)
    }
}
