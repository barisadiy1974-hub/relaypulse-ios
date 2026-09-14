import Foundation
import Network
import SwiftUI
import WidgetKit
import UserNotifications

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
    /// talking to StoreKit itself. Seeded from the same cache PurchaseStore
    /// writes, because this store is built before StoreKit answers and the
    /// first widget summary would otherwise be published for a 3-relay fleet.
    @Published var isEntitled = UserDefaults.standard.bool(forKey: PurchaseStore.entitledKey)

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
    @Published private(set) var statuses: [String: RelayStatus] = [:] { didSet { publishWidgetSummary(sweepDone: false) } }
    @Published private(set) var isPolling = false
    /// Set when a whole sweep failed at once — the phone's network, not the fleet.
    @Published private(set) var networkSuspect = false
    /// True while iOS reports this device has no usable network path. A phone in
    /// a tunnel is the commonest cause of "all my servers went down at once".
    @Published private(set) var deviceOffline = false

    private let pathMonitor = NWPathMonitor()
    @Published private(set) var lastSweep: Date? { didSet { publishWidgetSummary(sweepDone: true) } }
    @Published var pollSec: Int = 120
    @Published var offlineAfter: Int = 3
    @Published private(set) var bridge: MacBridge?

    /// One relay's result from a sweep, plus what the sweep learned on the way:
    /// a token read back off the relay after a 403, and whether a token problem
    /// is still outstanding.
    private struct SweepOutcome {
        let name: String
        let result: Result<AgentMetrics, Error>
        var repairedToken: String? = nil
        var tokenStale: Bool = false
        var certChanged: Bool = false
    }

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
        // Watch the phone's own connection. Without this the app cannot tell
        // "the servers are down" from "I am in a tunnel", and it wakes the
        // operator for the second one.
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.deviceOffline = path.status != .satisfied }
        }
        pathMonitor.start(queue: DispatchQueue(label: "relaypulse.path"))
    }

    var isConfigured: Bool { !servers.isEmpty }

    // Summed over the monitored slice, not every status. A relay that drops out
    // of that slice (the free tier keeps the first few by name, so a rename can
    // shuffle it out) stops being polled but keeps its last reading, and summing
    // the dictionary kept counting that frozen number as live bandwidth.
    var totalRxMbps: Double { monitoredServers.reduce(0) { $0 + (statuses[$1.name]?.rxMbps ?? 0) } }
    var totalTxMbps: Double { monitoredServers.reduce(0) { $0 + (statuses[$1.name]?.txMbps ?? 0) } }

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

    private var lastWidgetCounts: [Int] = []

    /// Widget'in okudugu ozet. Relay basina son bilinen durum plist'te tutulur:
    /// app arka plana alininca tur yarim kaliyor ve arka plan turu 10 relay
    /// sorguluyor; sorgulanmayanlar `.unknown` kalip sayimi dusuruyordu
    /// (143 filoda 139-141 gorundu). Sayilar degisince hemen yazilir; egriye
    /// nokta yalniz tur sonunda eklenir ki tirmanis kaydedilmesin.
    private func publishWidgetSummary(sweepDone: Bool) {
        let prev = FleetSummary.load()
        let pool = monitoredServers
        // Hatirlanan durum yalnizca relay yapilandirmadan cikinca silinir.
        // Once izlenen dilime gore suzuluyordu; o dilim acilista bir tur kisa
        // kaliyor (hak StoreKit'ten asenkron geliyor), yani her soguk acilis
        // 143 relay'in 140'inin hafizasini siliyor ve widget sayisi arka plan
        // turlariyla onar onar geri tirmaniyordu.
        var states = (prev?.states ?? [:]).filter { st in servers.contains { $0.name == st.key } }
        for srv in pool {
            if let st = statuses[srv.name], st.state != .unknown { states[srv.name] = st.state.rawValue }
        }
        let monitored = Set(pool.map(\.name))
        var s = FleetSummary(total: pool.count)
        for (name, v) in states where monitored.contains(name) {
            switch RelayState(rawValue: v) {
            case .online:  s.online += 1
            case .warn:    s.warn += 1
            case .stale:   s.stale += 1
            case .offline: s.offline += 1
            default: break
            }
        }
        let counts = [s.total, s.online, s.warn, s.stale, s.offline]
        guard sweepDone || counts != lastWidgetCounts else { return }
        lastWidgetCounts = counts
        let worst = pool.compactMap { statuses[$0.name] }
            .filter { $0.state == .offline || $0.state == .warn }
            .sorted { ($0.state == .offline ? 1 : 0, $0.fails) > ($1.state == .offline ? 1 : 0, $1.fails) }
            .first
        if let w = worst {
            s.worstName = w.name
            s.worstError = w.state == .offline ? "SSH yok" : w.anonLabel
            s.worstSince = w.lastUpdated
        } else if let n = states.first(where: { $0.value == RelayState.offline.rawValue })?.key {
            s.worstName = n; s.worstError = "SSH yok"
        }
        s.states = states
        s.history = prev?.history ?? []
        if sweepDone { s.history = Array((s.history + [s.online]).suffix(48)) }
        s.save()
        WidgetCenter.shared.reloadAllTimelines()
        // Same numbers on the lock screen, with a counter that keeps running
        // between polls.
        if #available(iOS 16.2, *) {
            OutageActivity.sync(worstName: s.worstName, offlineCount: s.offline, since: s.worstSince)
        }
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
        // Importing a real fleet is an unambiguous "done looking around".
        // Leaving demo on would show the imported relays next to demo statuses
        // that a ticker keeps overwriting every 5s.
        if demoMode { demoMode = false }
        apply(export)
    }

    func clearConfig() {
        guard !demoMode else { return }
        timer?.cancel(); timer = nil
        servers = []; statuses = [:]; samples = [:]; lastSweep = nil
        ServerStorage.clear()
    }

    // MARK: - Add / edit / remove relay

    /// The demo fleet is a display, not a configuration. While it is on,
    /// `servers` holds sample relays, so any edit that reached storage would
    /// write those over the operator's real fleet — and deleting the last
    /// sample relay would call `clearConfig()` and erase it outright. Both are
    /// silent and permanent, and the demo switch sits on the same screen as the
    /// relay list, so this is one swipe away. Settings hides those controls in
    /// demo mode too; this is the backstop.
    private func persistCurrent() {
        guard !demoMode else { return }
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

    /// Updates an existing relay. `originalName` carries the old record if the
    /// name changed. Renaming onto a name already in use is refused: `Server.id`
    /// is the name, so two records would share an identity — the list renders
    /// wrong, `removeServer` deletes both, and the other relay's status is
    /// overwritten by the rename below.
    @discardableResult
    func updateServer(_ s: Server, originalName: String) -> Bool {
        guard !s.name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard let idx = servers.firstIndex(where: { $0.name == originalName }) else { return false }
        if s.name != originalName {
            guard !servers.contains(where: { $0.name == s.name }) else { return false }
            statuses[s.name] = statuses.removeValue(forKey: originalName) ?? RelayStatus(name: s.name)
            samples[s.name] = samples.removeValue(forKey: originalName)
        }
        servers[idx] = s
        servers.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        persistCurrent()
        return true
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
        // No network here means every request would fail and every relay would
        // march toward red for a reason that has nothing to do with the relays.
        guard !deviceOffline else {
            networkSuspect = true
            return
        }
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
        // Worked out here, on the main actor, before the task group starts: the
        // tasks run off-actor and cannot read `statuses`. A relay is "critical"
        // when one more failure would mark it offline.
        let critical = Set(targets
            .filter { (statuses[$0.name]?.fails ?? 0) + 1 >= offlineAfter }
            .map(\.name))
        // On a 403 the token is repaired over SSH and the fetch retried, the way
        // desktop RelayPulse has always done it (monitor.js). `repairedToken`
        // carries the new value back so it can be stored; `tokenStale` marks the
        // relays that could not be repaired, so the SSH fallback does not
        // quietly cover for a dead token forever — the card would look perfect
        // and the relay would vanish the day the SSH key changed.
        await withTaskGroup(of: SweepOutcome.self) { group in
            var iterator = targets.makeIterator()
            // Simultaneous TLS handshakes to 143 hosts caused transient errors — window of 10.
            let maxInFlight = 10

            func addNext() {
                guard let s = iterator.next() else { return }
                let isCritical = critical.contains(s.name)
                group.addTask {
                    do { return SweepOutcome(name: s.name, result: .success(try await AgentClient.shared.fetch(s))) }
                    catch {
                        var tokenStale = false
                        // A refused certificate pin must not vanish just because
                        // SSH can still read the metrics: it is the one failure
                        // here that can mean someone is in the middle.
                        var certChanged = false
                        if let e = error as? AgentError, case .certChanged = e { certChanged = true }
                        if let e = error as? AgentError, case .badToken = e {
                            tokenStale = true
                            // Read the relay's real token and try again with it.
                            // The token drifts for ordinary reasons — rebuilding a
                            // relay regenerates it, and a fleet exported to this
                            // phone is a snapshot that ages — so healing beats
                            // asking the operator to go and find the new value.
                            if let fixed = await SSHMetrics.shared.repairToken(s) {
                                var repaired = s
                                repaired.agentToken = fixed
                                if let m = try? await AgentClient.shared.fetch(repaired) {
                                    return SweepOutcome(name: s.name, result: .success(m),
                                                        repairedToken: fixed)
                                }
                            }
                        }
                        // Agent unreachable — ask over SSH before calling the relay
                        // down, which is what the desktop app does. Measured
                        // 2026-09-03: ~1% of a 143-host sweep loses its agent reply
                        // purely to transient noise while the box answers SSH fine,
                        // and that was the whole reason the phone showed yellow for
                        // relays the Mac showed green. Costs an SSH round trip on
                        // roughly one or two relays per sweep.
                        if let m = await SSHMetrics.shared.fetch(s, critical: isCritical) {
                            return SweepOutcome(name: s.name, result: .success(m),
                                                tokenStale: tokenStale, certChanged: certChanged)
                        }
                        return SweepOutcome(name: s.name, result: .failure(error),
                                            tokenStale: tokenStale, certChanged: certChanged)
                    }
                }
            }
            for _ in 0..<maxInFlight { addNext() }
            var outcomes: [SweepOutcome] = []
            for await outcome in group {
                // Store a repaired token first, so the next sweep uses it.
                if let token = outcome.repairedToken { applyRepairedToken(outcome.name, token) }
                outcomes.append(outcome)
                addNext()
            }

            // Judged over the whole sweep, not relay by relay: when this many
            // hosts fail at once the phone lost its network, not the fleet.
            // Measured 2026-09-13 on the watcher that polls the same fleet from
            // a server: one two-hour network wobble produced 55 false "offline"
            // alarms while every relay was up. Recording those failures would
            // march healthy relays to red and wake the operator for nothing.
            let failed = outcomes.filter { if case .failure = $0.result { return true }; return false }.count
            networkSuspect = FleetStore.fleetWideFailure(failed: failed, total: outcomes.count)

            for outcome in outcomes {
                switch outcome.result {
                case .success(let m):
                    recordSuccess(outcome.name, m)
                    // Readings are real — SSH fetched them — but the token could
                    // not be repaired, so say so rather than showing green.
                    if outcome.tokenStale && outcome.repairedToken == nil {
                        markTokenStale(outcome.name)
                    }
                    if outcome.certChanged { markCertChanged(outcome.name) }
                case .failure(let e):
                    // Suppressed, and the fail counter is left alone: our own
                    // outage must not push anyone's relay toward red.
                    guard !networkSuspect else { continue }
                    recordFailure(outcome.name, e)
                    // One more try before the card turns red and the phone
                    // rings. Measured 2026-09-14 on a 140-relay fleet: every
                    // single-relay alarm that night cleared on the next poll,
                    // i.e. none of them were real. A confirmation costs one
                    // request; a false alarm costs the operator's sleep.
                    if statuses[outcome.name]?.state == .offline,
                       let server = targets.first(where: { $0.name == outcome.name }),
                       let m = try? await AgentClient.shared.fetch(server) {
                        recordSuccess(outcome.name, m)
                    }
                }
            }
        }
        lastSweep = Date()
    }

    /// True when so much of one sweep failed that the network here is the
    /// likelier explanation. Pure so the check is testable without a fleet.
    /// Two rules, because fleets come in two shapes.
    /// - Every server failing at once (two or more) is almost never the servers;
    ///   a customer watching three machines loses all three when the phone drops
    ///   its connection, and the old "at least five" rule never covered them.
    /// - On a large fleet a tenth failing in one sweep is the same signal.
    static func fleetWideFailure(failed: Int, total: Int) -> Bool {
        guard total > 0, failed > 0 else { return false }
        if total >= 2 && failed == total { return true }
        return failed >= max(5, Int((Double(total) * 0.10).rounded(.up)))
    }

    // MARK: - Result processing + flap dampening

    private func recordSuccess(_ name: String, _ m: AgentMetrics) {
        var st = statuses[name] ?? RelayStatus(name: name)
        // Only .offline: that is the state that woke the operator up, so that is
        // the one worth telling them is over. A stale relay never notified.
        let wasOffline = st.state == .offline
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
        if wasOffline { notifyRecovered(name, anonHealthy: m.anonHealthy, anonLabel: m.anonLabel) }
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

    /// Stores a token read back off the relay after a 403. Runs on the main
    /// actor, which is what keeps concurrent repairs from overwriting each
    /// other — the desktop needed an explicit save queue for exactly this, since
    /// several relays can answer 403 in the same sweep.
    private func applyRepairedToken(_ name: String, _ token: String) {
        guard let idx = servers.firstIndex(where: { $0.name == name }),
              servers[idx].agentToken != token else { return }
        servers[idx].agentToken = token
        persistCurrent()
    }

    /// SSH covered for the agent, but the agent's certificate no longer matches
    /// the pinned key. Yellow rather than green — the readings are real, the
    /// agent connection is not to be trusted until the operator says why.
    private func markCertChanged(_ name: String) {
        guard var st = statuses[name] else { return }
        st.state = .warn
        st.lastError = AgentError.certChanged.errorDescription
        statuses[name] = st
    }

    /// Keeps the metrics SSH just fetched, but flags the out-of-date agent token
    /// so it gets fixed instead of being silently carried by the fallback.
    private func markTokenStale(_ name: String) {
        guard var st = statuses[name] else { return }
        st.state = .warn
        st.lastError = AgentError.badToken.errorDescription
        statuses[name] = st
    }

    /// Widget'taki "Onar" dugmesinin biraktigi istegi calistirir. Uygulama one
    /// geldiginde cagrilir: SSH oturumu ve filo anahtari burada, widget'ta degil.
    func runPendingFix() async {
        guard let req = PendingFix.take(),
              let srv = servers.first(where: { $0.name == req.relay }),
              let cmd = AppSettings.loadCommands().first else { return }
        do {
            let r = try await SSHRunner.shared.run(cmd.command, on: srv, timeout: 60)
            let ok = (r.exitStatus ?? 0) == 0
            let text = r.combined.isEmpty ? "(no output)" : r.combined
            AILog.shared.add(kind: .command, relay: srv.name, title: cmd.name, detail: text, ok: ok)
            notifyFix(srv.name, ok ? text : "Komut hata dondurdu", ok: ok)
            await sweep()
        } catch {
            AILog.shared.add(kind: .error, relay: srv.name, title: cmd.name,
                             detail: error.localizedDescription, ok: false)
            notifyFix(srv.name, error.localizedDescription, ok: false)
        }
    }

    /// Onarim sonucu: tetikleyen dokunus widget'ta oldugu icin kullanici
    /// uygulamanin neresine dustugunu bilmiyor; sonucu bildirimle soyle.
    private func notifyFix(_ name: String, _ detail: String, ok: Bool) {
        let c = UNMutableNotificationContent()
        c.title = String(format: NSLocalizedString(ok ? "relay.fixed" : "relay.fixFailed", comment: ""), name)
        c.body = String(detail.prefix(180))
        c.sound = ok ? nil : .default
        c.threadIdentifier = "relay-fix"
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "fix-\(name)", content: c, trigger: nil))
    }

    /// Sadece stale -> offline gecisinde; her basarisiz poll'da degil.
    private func notifyOffline(_ name: String, _ error: String?) {
        let c = UNMutableNotificationContent()
        c.title = String(format: NSLocalizedString("relay.offline.title", comment: ""), name)
        c.body = error ?? NSLocalizedString("relay.offline.body", comment: "")
        c.sound = .default
        c.threadIdentifier = "relay-offline"
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "offline-\(name)", content: c, trigger: nil))
    }

    /// Relay cevap verdi. Alarmi kapatan bildirim: gece kalkan operator
    /// telefona bakip bittigini gorebilsin diye — ve kilit ekranindaki eski
    /// cevrimdisi bildirimi de birakmasin.
    private func notifyRecovered(_ name: String, anonHealthy: Bool, anonLabel: String) {
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: ["offline-\(name)"])
        let c = UNMutableNotificationContent()
        c.title = String(format: NSLocalizedString("relay.recovered.title", comment: ""), name)
        // Ulasilabilir olmak saglikli olmak degil: SSH doner ama anon hala
        // kapali olabilir, ve o zaman "her sey yolunda" demek yanlis olur.
        c.body = anonHealthy
            ? NSLocalizedString("relay.recovered.body", comment: "")
            : String(format: NSLocalizedString("relay.recovered.anonDown", comment: ""), anonLabel)
        c.sound = nil
        c.threadIdentifier = "relay-offline"
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "recovered-\(name)", content: c, trigger: nil))
    }

    private func recordFailure(_ name: String, _ error: Error) {
        var st = statuses[name] ?? RelayStatus(name: name)
        // Our own errors carry English text; anything else is described rather
        // than localized, so the card never shows a translated system string.
        st.lastError = (error as? LocalizedError)?.errorDescription ?? SSHRunner.describe(error)

        // A 403 is not an outage. The agent answered — so the host is up, the
        // network path is fine, and only the stored token is out of date.
        // Counting it toward the offline threshold painted a perfectly healthy
        // relay red and sent the operator debugging a machine that was working;
        // it also let one mis-configured relay accumulate failures forever.
        // Warn instead, and hold the counter so it never decays to offline.
        if let e = error as? AgentError, case .badToken = e {
            st.state = .warn
            st.fails = 0
            statuses[name] = st
            return
        }

        st.fails += 1
        // lastUpdated deliberately untouched: it is the last time the relay was
        // actually reached, and the card shows it as "x ago". Stamping it here
        // made a host that had been unreachable for hours read "2s ago" — the
        // failure resetting the very clock that measures how stale the reading is.
        // Red after offlineAfter misses, yellow one miss earlier. A SINGLE missed
        // poll keeps the last good reading and stays green: measured 2026-09-03,
        // ~1% of a 143-host sweep fails transiently while those same hosts answer
        // in ~105ms when probed on their own. Matches the desktop app's threshold.
        let staleAfter = max(1, offlineAfter - 1)
        if st.fails >= offlineAfter {
            if st.state != .offline { notifyOffline(name, st.lastError) }
            st.state = .offline
        } else if st.fails >= staleAfter {
            st.state = .stale
        }
        // Below the threshold the state is left alone rather than set to
        // .online. Writing green there meant a failed poll could *raise* a
        // relay's status: a warn (anon service down) went green until the next
        // success, and a brand-new relay with a wrong IP showed green for its
        // first poll before decaying to yellow and red.
        statuses[name] = st
    }
}
