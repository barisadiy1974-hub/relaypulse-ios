import Foundation
import SwiftUI

@MainActor
final class FleetStore: ObservableObject {
    /// Single instance so the background-refresh task registered in
    /// AppDelegate operates on the same store the UI shows.
    static let shared = FleetStore()

    /// Demo modu: gercek filo yerine uydurma veri gosterilir. App Review'in
    /// uygulamayi test edebilmesi ve magaza gorsellerinin gercek filo verisi
    /// icermemesi icin gerekli. Ag baglantisi kurulmaz.
    @Published var demoMode: Bool = UserDefaults.standard.bool(forKey: "demoMode") {
        didSet {
            UserDefaults.standard.set(demoMode, forKey: "demoMode")
            applyDemoMode()
        }
    }

    /// How many relays the app watches before it is paid for. The free tier is
    /// the whole app on a smaller fleet — nothing is switched off, the slice
    /// being monitored is just shorter. Matches the desktop build.
    static let freeRelayLimit = 3

    /// Kept in sync from PurchaseStore by RootView; FleetStore has no business
    /// talking to StoreKit itself.
    @Published var isEntitled = false

    /// Everything the operator has configured. Always complete: the limit
    /// applies to what gets polled, never to what they can see or edit, so
    /// nobody's server list is silently truncated.
    @Published private(set) var servers: [Server] = []

    /// The slice actually monitored. Demo fleets are never capped — the point
    /// of the demo is to show what a real fleet looks like.
    var monitoredServers: [Server] {
        (isEntitled || demoMode) ? servers : Array(servers.prefix(Self.freeRelayLimit))
    }

    var isRelayLimited: Bool { monitoredServers.count < servers.count }
    @Published private(set) var statuses: [String: RelayStatus] = [:]
    @Published private(set) var isPolling = false
    @Published private(set) var lastSweep: Date?
    @Published var pollSec: Int = 120
    @Published var offlineAfter: Int = 3
    @Published private(set) var bridge: MacBridge?

    /// Previous samples for delta calculations (rx/tx bytes, cpu idle/total, timestamp).
    private struct Sample { var rx: Double; var tx: Double; var cpuIdle: Double; var cpuTotal: Double; var at: Date }
    private var samples: [String: Sample] = [:]

    private var timer: Task<Void, Never>?

    private var demoTimer: Task<Void, Never>?
    private var backgroundCursor = 0

    init() {
        if let export = ServerStorage.load() {
            apply(export, persist: false)
        }
    }

    var isConfigured: Bool { !servers.isEmpty }

    var totalRxMbps: Double { statuses.values.reduce(0) { $0 + ($1.rxMbps ?? 0) } }
    var totalTxMbps: Double { statuses.values.reduce(0) { $0 + ($1.txMbps ?? 0) } }

    var aggregate: (total: Int, online: Int, stale: Int, offline: Int, warn: Int) {
        let pool = monitoredServers
        var a = (total: pool.count, online: 0, stale: 0, offline: 0, warn: 0)
        for s in pool {
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
        // iPhone kendi agent baglantilarini kullanir; Mac'in acik olmasina
        // veya yerel bridge API'sine bagimli degildir.
        bridge = nil
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
                                       pollSec: pollSec, offlineAfter: offlineAfter, bridge: bridge,
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

    /// Demo acilinca uydurma filo yuklenir; kapaninca kaydedilmis gercek
    /// yapilandirmaya donulur.
    func applyDemoMode() {
        if demoMode {
            stopPolling()
            servers = DemoFleet.servers
            statuses = DemoFleet.statuses()
            lastSweep = Date()
            startDemoTicker()
        } else {
            stopDemoTicker()
            statuses = [:]
            servers = []
            if let export = ServerStorage.load() { apply(export, persist: false) }
            startPolling()
        }
    }

    private func startDemoTicker() {
        stopDemoTicker()
        demoTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run {
                    guard let self, self.demoMode else { return }
                    self.statuses = DemoFleet.statuses()
                    self.lastSweep = Date()
                }
            }
        }
    }

    private func stopDemoTicker() { demoTimer?.cancel(); demoTimer = nil }

    func startPolling() {
        guard !demoMode else { applyDemoMode(); return }
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
        await sweep(monitoredServers)
    }

    /// iOS arka plan yenilemesi en fazla kisa bir calisma suresi verir. Tum
    /// filoyu yeniden baglamaya calismak yerine her seferinde donusen kucuk bir
    /// grup kontrol edilir; uygulama yeniden one gelince normal tam tur devam eder.
    func refreshInBackground() async {
        let pool = monitoredServers
        guard !pool.isEmpty else { return }
        let batchSize = min(10, pool.count)
        let start = backgroundCursor % pool.count
        let targets = (0..<batchSize).map { pool[(start + $0) % pool.count] }
        backgroundCursor = (start + batchSize) % pool.count
        await sweep(targets)
    }

    private func sweep(_ targets: [Server]) async {
        guard !demoMode else { return }   // demo veride ag baglantisi kurulmaz
        guard !isPolling, isConfigured else { return }
        isPolling = true
        defer { isPolling = false }

        if let bridge {
            do {
                let payload = try await BridgeClient.fetch(bridge)
                let byName = Dictionary(uniqueKeysWithValues: payload.relays.map { ($0.name, $0) })
                for s in targets {
                    if let r = byName[s.name] { recordBridgeSuccess(r) }
                    else { recordFailure(s.name, BridgeClient.BridgeError.decode("relay missing from Mac snapshot")) }
                }
            } catch {
                for s in targets { recordFailure(s.name, error) }
            }
            lastSweep = Date()
            return
        }
        // Cap how much SSH fallback this sweep may spend (see SSHMetrics).
        await SSHMetrics.shared.startSweep()
        await withTaskGroup(of: (String, Result<AgentMetrics, Error>).self) { group in
            var iterator = targets.makeIterator()
            // Simultaneous TLS handshakes to 143 hosts caused transient errors — window of 10.
            let maxInFlight = 10

            func addNext() {
                guard let s = iterator.next() else { return }
                group.addTask {
                    do { return (s.name, .success(try await AgentClient.shared.fetch(s))) }
                    catch {
                        // Agent unreachable — ask over SSH before calling the relay
                        // down, which is what the desktop app does. Measured
                        // 2026-09-03: ~1% of a 143-host sweep loses its agent reply
                        // purely to transient noise while the box answers SSH fine,
                        // and that was the whole reason the phone showed yellow for
                        // relays the Mac showed green. Costs an SSH round trip on
                        // roughly one or two relays per sweep.
                        if let m = await SSHMetrics.shared.fetch(s) { return (s.name, .success(m)) }
                        return (s.name, .failure(error))
                    }
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

    private func recordBridgeSuccess(_ r: BridgeClient.Relay) {
        var st = statuses[r.name] ?? RelayStatus(name: r.name)
        st.fails = 0
        st.lastError = r.error
        st.lastUpdated = r.ts.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
        st.anonLabel = r.anon ?? "—"
        st.anonHealthy = r.anon == "active" || r.anon == "activating"
        st.conn = r.conn.map { Int($0) }; st.rxMbps = r.rxMbps; st.txMbps = r.txMbps
        st.memPct = r.memPct; st.cpuPct = r.cpuPct; st.publicIp = r.publicIp
        st.uptime = r.uptimeSec.map { String(format: "%.0fs", $0) }
        st.state = RelayState(rawValue: r.state) ?? (st.anonHealthy ? .online : .warn)
        statuses[r.name] = st
    }

    private func recordFailure(_ name: String, _ error: Error) {
        var st = statuses[name] ?? RelayStatus(name: name)
        st.fails += 1
        st.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        st.lastUpdated = Date()
        // Red after offlineAfter misses, yellow one miss earlier. A SINGLE missed
        // poll keeps the last good reading and stays green: measured 2026-09-03,
        // ~1% of a 143-host sweep fails transiently while those same hosts answer
        // in ~105ms when probed on their own. Matches the desktop app's threshold.
        let staleAfter = max(1, offlineAfter - 1)
        st.state = st.fails >= offlineAfter ? .offline
            : st.fails >= staleAfter ? .stale
            : .online
        statuses[name] = st
    }
}
