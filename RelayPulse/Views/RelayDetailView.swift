import SwiftUI

struct RelayDetailView: View {
    @EnvironmentObject var fleet: FleetStore
    @Environment(\.colorScheme) private var scheme
    let server: Server
    @State private var showEdit = false

    private var status: RelayStatus { fleet.status(for: server) }
    private var sc: Color { status.state.color(scheme) }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                PanelCard(stateColor: sc) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Circle().fill(sc).frame(width: 10, height: 10)
                            Text(status.state.label).font(.headline).foregroundStyle(sc)
                            Spacer()
                            Text(status.ageText + " önce").font(.caption).foregroundStyle(Theme.muted(scheme))
                        }
                        if status.fails > 0 {
                            Text("\(status.fails) ardışık başarısız poll").font(.caption).foregroundStyle(Theme.warn(scheme))
                        }
                        if let e = status.lastError {
                            Text(e).font(.caption).foregroundStyle(Theme.err(scheme))
                        }
                    }
                }

                infoCard("Metrikler", [
                    ("anon servisi", status.anonLabel),
                    ("Bağlantı", status.conn.map { "\($0)" } ?? "—"),
                    ("İndirme", mbps(status.rxMbps)),
                    ("Yükleme", mbps(status.txMbps)),
                    ("CPU", (status.cpuPct.map { "\(Int($0))%" } ?? "—") + (status.cpuCount.map { " · \($0) çekirdek" } ?? "")),
                    ("RAM", status.memPct.map { "\(Int($0))%" } ?? "—"),
                    ("Disk", status.diskPct.map { "\(Int($0))%" } ?? "—"),
                    ("Yük ort.", status.load.map { l in l.count == 3 ? String(format: "%.2f  %.2f  %.2f", l[0], l[1], l[2]) : "—" } ?? "—"),
                    ("Uptime", status.uptime ?? "—"),
                ])

                infoCard("Sunucu", [
                    ("Host", "\(server.host):\(server.agentPort)"),
                    ("Şema", server.agentScheme.uppercased()),
                    ("Public IP", status.publicIp ?? "—"),
                    ("Cüzdan", server.wallet.isEmpty ? "—" : server.wallet),
                ])
            }
            .padding(12)
        }
        .background(Theme.bg(scheme))
        .navigationTitle(server.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Düzenle") { showEdit = true }
            }
        }
        .sheet(isPresented: $showEdit) { ServerEditView(mode: .edit(server)) }
        .refreshable { await fleet.sweep() }
    }

    private func infoCard(_ title: String, _ rows: [(String, String)]) -> some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 0) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold)).tracking(0.5)
                    .foregroundStyle(Theme.muted(scheme))
                    .padding(.bottom, 6)
                ForEach(rows.indices, id: \.self) { i in
                    HStack {
                        Text(rows[i].0).foregroundStyle(Theme.muted(scheme))
                        Spacer()
                        Text(rows[i].1)
                            .foregroundStyle(Theme.text(scheme))
                            .multilineTextAlignment(.trailing)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .font(.system(size: 13))
                    .padding(.vertical, 5)
                    if i < rows.count - 1 { Divider().overlay(Theme.border(scheme)) }
                }
            }
        }
    }

    private func mbps(_ v: Double?) -> String {
        guard let v else { return "—" }
        return String(format: v < 10 ? "%.2f Mbps" : "%.0f Mbps", v)
    }
}
