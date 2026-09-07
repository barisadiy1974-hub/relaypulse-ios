import SwiftUI

/// Fleet Health — the whole fleet's pulse on one screen.
/// Everything is derived from data already collected by FleetStore; no extra requests.
struct FleetHealthView: View {
    @EnvironmentObject var fleet: FleetStore
    @Environment(\.colorScheme) private var scheme

    /// The monitored slice only, same as the Relays tab and the summary card
    /// above. Listing an unpolled relay here would rank it by a reading that
    /// stopped updating.
    private var rows: [(Server, RelayStatus)] {
        fleet.monitoredServers.map { ($0, fleet.status(for: $0)) }
    }

    /// Needs attention: offline → warning → stale, worst first.
    private var problems: [(Server, RelayStatus)] {
        rows.filter { $0.1.state == .offline || $0.1.state == .stale || $0.1.state == .warn }
            .sorted { a, b in rank(a.1.state) < rank(b.1.state) }
    }

    private func rank(_ s: RelayState) -> Int {
        switch s {
        case .offline: return 0
        case .warn:    return 1
        case .stale:   return 2
        default:       return 3
        }
    }

    private var ramHot: [(Server, RelayStatus)] { rows.filter { ($0.1.memPct ?? 0) >= 90 }.sorted { ($0.1.memPct ?? 0) > ($1.1.memPct ?? 0) } }
    private var diskHot: [(Server, RelayStatus)] { rows.filter { ($0.1.diskPct ?? 0) >= 85 }.sorted { ($0.1.diskPct ?? 0) > ($1.1.diskPct ?? 0) } }
    private var cpuHot: [(Server, RelayStatus)] { rows.filter { ($0.1.cpuPct ?? 0) >= 80 }.sorted { ($0.1.cpuPct ?? 0) > ($1.1.cpuPct ?? 0) } }
    private var busiest: [(Server, RelayStatus)] {
        rows.filter { ($0.1.rxMbps ?? 0) + ($0.1.txMbps ?? 0) > 0 }
            .sorted { (($0.1.rxMbps ?? 0) + ($0.1.txMbps ?? 0)) > (($1.1.rxMbps ?? 0) + ($1.1.txMbps ?? 0)) }
            .prefix(5).map { $0 }
    }
    private var totalConn: Int { rows.compactMap { $0.1.conn }.reduce(0, +) }
    private var avgMem: Double? {
        let v = rows.compactMap { $0.1.memPct }
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }

    var body: some View {
        NavStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    FleetSummaryCard(agg: fleet.aggregate, totalRx: fleet.totalRxMbps, totalTx: fleet.totalTxMbps)

                    PanelCard {
                        HStack {
                            big("\(totalConn)", "Total connections", Theme.accent(scheme))
                            Divider().frame(height: 34).overlay(Theme.border(scheme))
                            big(avgMem.map { "\(Int($0))%" } ?? "—", "Average RAM", Theme.text(scheme))
                        }
                    }

                    if problems.isEmpty {
                        PanelCard(stateColor: Theme.ok(scheme)) {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.ok(scheme))
                                Text("All relays healthy")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.text(scheme))
                            }
                        }
                    } else {
                        section("Needs attention (\(problems.count))") {
                            ForEach(problems, id: \.0.id) { s, st in
                                NavigationLink {
                                    RelayDetailView(server: s)
                                } label: {
                                    problemRow(s, st)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !ramHot.isEmpty {
                        section("RAM critical (≥90%)") { list(ramHot) { "\(Int($0.memPct ?? 0))%" } }
                    }
                    if !diskHot.isEmpty {
                        section("Disk filling up (≥85%)") { list(diskHot) { "\(Int($0.diskPct ?? 0))%" } }
                    }
                    if !cpuHot.isEmpty {
                        section("CPU high (≥80%)") { list(cpuHot) { "\(Int($0.cpuPct ?? 0))%" } }
                    }
                    if !busiest.isEmpty {
                        section("Busiest 5 relays") {
                            list(busiest) { String(format: "%.1f Mbps", ($0.rxMbps ?? 0) + ($0.txMbps ?? 0)) }
                        }
                    }

                    if let t = fleet.lastSweep {
                        Text("Last sweep: \(t.formatted(date: .omitted, time: .standard))")
                            .font(.caption2).foregroundStyle(Theme.muted(scheme))
                            .frame(maxWidth: .infinity).padding(.top, 4)
                    }
                }
                .padding(.horizontal, 12).padding(.top, 6)
            }
            .background(Theme.bg(scheme))
            .navigationTitle("Fleet Health")
            .refreshable { await fleet.sweep() }
        }
    }

    // MARK: - Pieces

    private func big(_ v: String, _ l: String, _ c: Color) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(size: 22, weight: .bold).monospacedDigit()).foregroundStyle(c)
            Text(l).font(.system(size: 11)).foregroundStyle(Theme.muted(scheme))
        }
        .frame(maxWidth: .infinity)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold)).tracking(0.5)
                .foregroundStyle(Theme.muted(scheme))
                .padding(.leading, 4).padding(.top, 6)
            PanelCard { VStack(spacing: 0) { content() } }
        }
    }

    private func problemRow(_ s: Server, _ st: RelayStatus) -> some View {
        HStack(spacing: 10) {
            Circle().fill(st.state.color(scheme)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text(scheme))
                Text(st.lastError ?? (st.anonHealthy ? st.state.label : "anon: \(st.anonLabel)"))
                    .font(.caption2).foregroundStyle(Theme.muted(scheme)).lineLimit(1)
            }
            Spacer()
            Text(st.state.label).font(.system(size: 11, weight: .medium)).foregroundStyle(st.state.color(scheme))
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }

    private func list(_ items: [(Server, RelayStatus)], value: @escaping (RelayStatus) -> String) -> some View {
        ForEach(items.prefix(8), id: \.0.id) { s, st in
            // Inline destination: value-based navigation is iOS 16+.
            NavigationLink {
                RelayDetailView(server: s)
            } label: {
                HStack {
                    Circle().fill(st.state.color(scheme)).frame(width: 7, height: 7)
                    Text(s.name).font(.system(size: 13)).foregroundStyle(Theme.text(scheme))
                    Spacer()
                    Text(value(st))
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.text(scheme))
                }
                .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
        }
    }
}
