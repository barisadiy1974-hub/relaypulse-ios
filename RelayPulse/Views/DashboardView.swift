import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var fleet: FleetStore
    @State private var query = ""
    @State private var filter: RelayFilter = .all
    @State private var showSettings = false

    enum RelayFilter: String, CaseIterable {
        case all = "Hepsi", issues = "Sorunlu", online = "Online"
    }

    private var visible: [Server] {
        fleet.servers.filter { s in
            let st = fleet.status(for: s)
            let matchesQuery = query.isEmpty
                || s.name.localizedCaseInsensitiveContains(query)
                || s.host.localizedCaseInsensitiveContains(query)
            let matchesFilter: Bool = {
                switch filter {
                case .all: return true
                case .online: return st.state == .online
                case .issues: return st.state == .warn || st.state == .stale || st.state == .offline
                }
            }()
            return matchesQuery && matchesFilter
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SummaryBar(agg: fleet.aggregate)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                        .listRowSeparator(.hidden)
                }
                Section {
                    Picker("Filtre", selection: $filter) {
                        ForEach(RelayFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                }
                Section {
                    ForEach(visible) { server in
                        NavigationLink(value: server) {
                            RelayCardView(server: server, status: fleet.status(for: server))
                        }
                    }
                } footer: {
                    if let t = fleet.lastSweep {
                        Text("Son tarama: \(t.formatted(date: .omitted, time: .standard))")
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "Relay veya IP ara")
            .navigationTitle("Filo (\(fleet.servers.count))")
            .navigationDestination(for: Server.self) { server in
                RelayDetailView(server: server)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if fleet.isPolling {
                        ProgressView()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .refreshable { await fleet.sweep() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .task {
                fleet.startPolling()
                if fleet.lastSweep == nil { await fleet.sweep() }
            }
        }
    }
}

struct SummaryBar: View {
    let agg: (total: Int, online: Int, stale: Int, offline: Int, warn: Int)

    var body: some View {
        HStack(spacing: 10) {
            stat("\(agg.online)", "Online", .green)
            stat("\(agg.warn)", "Uyari", .orange)
            stat("\(agg.stale)", "Sark.", .yellow)
            stat("\(agg.offline)", "Kirmizi", .red)
        }
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold().monospacedDigit()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}
