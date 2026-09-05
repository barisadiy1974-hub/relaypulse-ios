import SwiftUI

/// Relays tab — fleet summary + filter + relay card list.
struct DashboardView: View {
    @EnvironmentObject var fleet: FleetStore
    @Environment(\.colorScheme) private var scheme
    @State private var query = ""
    @State private var filter: RelayFilter = .all
    @State private var showAdd = false

    enum RelayFilter: String, CaseIterable {
        case all = "All", issues = "Issues", online = "Online"
    }

    private var visible: [Server] {
        fleet.servers.filter { s in
            let st = fleet.status(for: s)
            let q = query.isEmpty
                || s.name.localizedCaseInsensitiveContains(query)
                || s.host.localizedCaseInsensitiveContains(query)
            let f: Bool = {
                switch filter {
                case .all: return true
                case .online: return st.state == .online
                case .issues: return st.state == .warn || st.state == .stale || st.state == .offline
                }
            }()
            return q && f
        }
    }

    var body: some View {
        NavStack {
            ScrollView {
                LazyVStack(spacing: 8) {
                    // Mağaza ekran görüntüsü modunda demo şeridi gizlenir; veri
                    // yine demo (sahte IP/isim), sadece pazarlama görseli temiz olsun.
                    if fleet.demoMode && !ProcessInfo.processInfo.arguments.contains("-screenshot") {
                        HStack(spacing: 8) {
                            Image(systemName: "eye.fill")
                            Text(DemoFleet.bannerText).font(.footnote.weight(.semibold))
                            Spacer()
                            Button("Turn off") { fleet.demoMode = false }
                                .font(.footnote.weight(.semibold))
                        }
                        .padding(10)
                        .background(Theme.warn(scheme).opacity(0.15))
                        .foregroundStyle(Theme.warn(scheme))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    FleetSummaryCard(agg: fleet.aggregate, totalRx: fleet.totalRxMbps, totalTx: fleet.totalTxMbps)

                    Picker("Filter", selection: $filter) {
                        ForEach(RelayFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 2)

                    // Bosken CTA: reviewer / yeni kullanici hemen bir demo goruyor.
                    // Ret gerekcesi 2.1: "bos ekran gorduk, app'i test edemedik".
                    if fleet.servers.isEmpty && !fleet.demoMode {
                        VStack(spacing: 14) {
                            Image(systemName: "server.rack")
                                .font(.system(size: 44))
                                .foregroundStyle(Theme.accent(scheme))
                            Text("No relays yet")
                                .font(.title3.weight(.semibold))
                            Text("Add your own Anyone relay from the + button, or explore a sample fleet to see how RelayPulse works.")
                                .font(.footnote)
                                .foregroundStyle(Theme.muted(scheme))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                            Button(action: { fleet.demoMode = true }) {
                                Label("Try Demo Fleet", systemImage: "eye.fill")
                                    .font(.body.weight(.semibold))
                                    .padding(.horizontal, 20).padding(.vertical, 12)
                                    .background(Theme.accent(scheme))
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    }
                    ForEach(visible) { server in
                        // Destination inline rather than value-based navigation:
                        // NavigationLink(value:) + navigationDestination are iOS 16+.
                        NavigationLink {
                            RelayDetailView(server: server)
                        } label: {
                            RelayCardView(server: server, status: fleet.status(for: server))
                        }
                        .buttonStyle(.plain)
                    }

                    if let t = fleet.lastSweep {
                        Text("Last sweep: \(t.formatted(date: .omitted, time: .standard))")
                            .font(.caption2)
                            .foregroundStyle(Theme.muted(scheme))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
            }
            .background(Theme.bg(scheme))
            .searchable(text: $query, prompt: "Search relay or IP")
            .navigationTitle("Relays (\(fleet.servers.count))")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if fleet.isPolling { ProgressView() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .refreshable { await fleet.sweep() }
            .sheet(isPresented: $showAdd) {
                ServerEditView(mode: .add)
            }
            .task {
                fleet.startPolling()
                if fleet.lastSweep == nil { await fleet.sweep() }
            }
        }
    }
}

/// Fleet summary card — four state counters plus total bandwidth.
struct FleetSummaryCard: View {
    @Environment(\.colorScheme) private var scheme
    let agg: (total: Int, online: Int, stale: Int, offline: Int, warn: Int)
    let totalRx: Double
    let totalTx: Double

    var body: some View {
        PanelCard {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    stat("\(agg.online)", "Online", Theme.ok(scheme))
                    stat("\(agg.warn)", "Warning", Theme.warn(scheme))
                    stat("\(agg.stale)", "Stale", Theme.warn(scheme))
                    stat("\(agg.offline)", "Offline", Theme.err(scheme))
                }
                Divider().overlay(Theme.border(scheme))
                HStack {
                    Label(String(format: "%.1f Mbps", totalRx), systemImage: "arrow.down")
                        .foregroundStyle(Theme.rx(scheme))
                    Spacer()
                    Text("\(agg.total) relays")
                        .foregroundStyle(Theme.muted(scheme))
                    Spacer()
                    Label(String(format: "%.1f Mbps", totalTx), systemImage: "arrow.up")
                        .foregroundStyle(Theme.tx(scheme))
                }
                .font(.system(size: 12, weight: .medium).monospacedDigit())
            }
        }
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .bold).monospacedDigit()).foregroundStyle(color)
            Text(label).font(.system(size: 10)).foregroundStyle(Theme.muted(scheme))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
