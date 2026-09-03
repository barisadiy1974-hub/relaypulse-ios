import Foundation
import SwiftUI

@MainActor
final class FleetStore: ObservableObject {
    @Published private(set) var servers: [Server] = []
    @Published private(set) var statuses: [String: RelayStatus] = [:]
    @Published private(set) var isPolling = false
    @Published private(set) var lastSweep: Date?
    @Published var pollSec: Int = 120
    @Published var offlineAfter: Int = 2

    /// Previous samples for delta calculations (rx/tx bytes, cpu idle/total, timestamp).
    private struct Sample { var rx: Double; var tx: Double; var cpuIdle: Double; var cpuTotal: Double; var at: Date }
    private var samples: [String: Sample] = [:]

    private var timer: Task<Void, Never>?

    init() {
        if let export = ServerStorage.load() {
            apply(export, persist: false)
        }
    }

    var isConfigured: Bool { !servers.isEmpty }

    var totalRxMbps: Double { statuses.values.reduce(0) { $0 + ($1.rxMbps ?? 0) } }
    var totalTxMbps: Double { statuses.values.reduce(0) { $0 + ($1.txMbps ?? 0) } }

    var aggregate: (total: Int, online: Int, stale: Int, offline: Int, warn: Int) {
        var a = (total: servers.count, online: 0, stale: 0, offline: 0, warn: 0)
        for s in servers {
            switch statuses[s.name]?.state ?? .unknown {
            case .online:  a.online += 1
            case .warn:    a.warn += 1
            case .stale:   a.stale += 1
            case .offline: a.offline += 1
            case .unknown: break
            }
        }
        return a
    }

    func status(for server: Server) -> RelayStatus {
        statuses[server.name] ?? RelayStatus(name: server.name)
    }

    // MARK: - Config import

    func apply(_ export: FleetExport, persist: Bool = true) {
        servers = export.servers.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if let p = export.pollSec { pollSec = max(30, p) }
        if let o = export.offlineAfter { offlineAfter = max(1, o) }
        var next: [String: RelayStatus] = [:]
        for s in servers { next[s.name] = statuses[s.name] ?? RelayStatus(name: s.name) }
        statuses = next
        samples = samples.filter { key, _ in next[key] != nil }
        if persist { ServerStorage.save(export) }
    }

    func importConfig(from data: Data) throws {
        let export = try JSONDecoder().decode(FleetExport.self, from: data)
        guard !export.servers.isEmpty else {
            throw NSError(domain: "RelayPulse", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No servers found in file"])
        }
        apply(export)
    }

    func clearConfig() {
        timer?.cancel(); timer = nil
        servers = []; statuses = [:]; samples = [:]; lastSweep = nil
        ServerStorage.clear()
    }

    // MARK: - Add / edit / remove relay

    private func persistCurrent() {
        ServerStorage.save(FleetExport(exportedAt: Date().timeIntervalSince1970,
                                       pollSec: pollSec, offlineAfter: offlineAfter,
                                       servers: servers))
    }

    /// Adds a relay (name must be unique). Does not overwrite existing names.
    @discardableResult
    func addServer(_ s: Server) -> Bool {
        guard !s.name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard !servers.contains(where: { $0.name == s.name }) else { return false }
        servers.append(s)
        servers.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        statuses[s.name] = RelayStatus(name: s.name)
        persistCurrent()
        if timer == nil { startPolling() }
        return true
    }

    /// Updates an existing relay. `originalName` carries the old record if the name changed.
    func updateServer(_ s: Server, originalName: String) {
        guard let idx = servers.firstIndex(where: { $0.name == originalName }) else { return }
        if s.name != originalName {
            statuses[s.name] = statuses.removeValue(forKey: originalName) ?? RelayStatus(name: s.name)
            samples[s.name] = samples.removeValue(forKey: originalName)
        }
        servers[idx] = s
        servers.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        persistCurrent()
    }

    func removeServer(named name: String) {
        servers.removeAll { $0.name == name }
        statuses.removeValue(forKey: name)
        samples.removeValue(forKey: name)
        persistCurrent()
        if servers.isEmpty { clearConfig() }
    }

    func persistSettings() { persistCurrent() }

    // MARK: - Poll loop

    func startPolling() {
        guard timer == nil, isConfigured else { return }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sweep()
                let secs = await MainActor.run { self?.pollSec ?? 120 }
                try? await Task.sleep(nanoseconds: UInt64(secs) * 1_000_000_000)
            }
        }
    }

    func stopPolling() {
        timer?.cancel(); timer = nil
    }

    func sweep() async {
        guard !isPolling, isConfigured else { return }
        isPolling = true
        defer { isPolling = false }

        let targets = servers
        await withTaskGroup(of: (String, Result<AgentMetrics, Error>).self) { group in
            var iterator = targets.makeIterator()
            // Simultaneous TLS handshakes to 143 hosts caused transient errors — window of 10.
            let maxInFlight = 10

            func addNext() {
                guard let s = iterator.next() else { return }
                group.addTask {
                    do { return (s.name, .success(try await AgentClient.shared.fetch(s))) }
                    catch { return (s.name, .failure(error)) }
                }
            }
            for _ in 0..<maxInFlight { addNext() }
            for await (name, result) in group {
                switch result {
                case .success(let m): recordSuccess(name, m)
                case .failure(let e): recordFailure(name, e)
                }
                addNext()
            }
        }
        lastSweep = Date()
    }

    // MARK: - Result processing + flap dampening

    private func recordSuccess(_ name: String, _ m: AgentMetrics) {
        var st = statuses[name] ?? RelayStatus(name: name)
        let now = Date()

        // rx/tx Mbps + cpu% delta — same logic as monitor.js
        if let net = m.net, let prev = samples[name] {
            let dt = now.timeIntervalSince(prev.at)
            if dt > 0 {
                st.rxMbps = max(0, (net.rx - prev.rx) * 8 / 1_000_000 / dt)
                st.txMbps = max(0, (net.tx - prev.tx) * 8 / 1_000_000 / dt)
            }
        }
        if let cpu = m.cpu, let prev = samples[name] {
            let di = cpu.idle - prev.cpuIdle
            let dtot = cpu.total - prev.cpuTotal
            if dtot > 0 { st.cpuPct = max(0, min(100, (dtot - di) / dtot * 100)) }
        }
        samples[name] = Sample(rx: m.net?.rx ?? 0, tx: m.net?.tx ?? 0,
                               cpuIdle: m.cpu?.idle ?? 0, cpuTotal: m.cpu?.total ?? 0, at: now)

        st.fails = 0
        st.lastError = nil
        st.lastUpdated = now
        st.anonHealthy = m.anonHealthy
        st.anonLabel = m.anonLabel
        st.conn = m.conn.map { Int($0) }
        st.memPct = m.mem?.pct
        st.load = m.load
        st.diskPct = m.disk?.usedPct
        st.uptime = m.uptime
        st.publicIp = m.publicIp
        st.cpuCount = m.cpuCount
        st.state = m.anonHealthy ? .online : .warn
        statuses[name] = st
    }

    private func recordFailure(_ name: String, _ error: Error) {
        var st = statuses[name] ?? RelayStatus(name: name)
        st.fails += 1
        st.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        st.lastUpdated = Date()
        // Show "stale" (yellow) for offlineAfter-1 failures before going fully offline.
        st.state = st.fails >= offlineAfter ? .offline : .stale
        statuses[name] = st
    }
}
