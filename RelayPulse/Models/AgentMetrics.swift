import Foundation

/// agent.py'nin /metrics ciktisi. net / disk / cpu alanlari null gelebilir.
struct AgentMetrics: Decodable {
    struct Net: Decodable { var iface: String?; var rx: Double; var tx: Double }
    struct Mem: Decodable { var totalMB: Double?; var usedMB: Double?; var pct: Double? }
    struct Disk: Decodable { var totalKB: Double?; var usedKB: Double?; var availKB: Double?; var usedPct: Double? }
    struct Cpu: Decodable { var idle: Double; var total: Double }
    struct Anon: Decodable {
        var active: String?
        var ports: [String]?
        var services: [String: String]?
    }

    var ts: Double?
    var iface: String?
    var net: Net?
    var conn: Double?
    var mem: Mem?
    var load: [Double]?
    var disk: Disk?
    var cpu: Cpu?
    var cpuCount: Int?
    var anon: Anon?
    var uptime: String?
    var publicIp: String?
    /// 2 from agent.py v2 on; nil from v1.
    var agentVersion: Int?
    /// agent.py v2: every relay of the box, keyed like Server.agentInstanceKey
    /// ("" first relay, "2" for anon2 / anonrc-2, NAME for anon@NAME).
    var instances: [String: Instance]?

    struct Instance: Decodable {
        var unit: String?
        var nickname: String?
        var fingerprint: String?
        var services: [String: String]?
        var ports: [String]?
        var conn: Double?
    }

    /// This box's reading narrowed to one of its relays (agent.py v2): its own
    /// unit state, ports and connections; CPU / RAM / disk / traffic stay the
    /// box's. Nil when the agent does not report that relay (v1, or no such relay).
    func forInstance(_ key: String) -> AgentMetrics? {
        guard let i = instances?[key] else { return nil }
        let services = i.services ?? [:]
        let ports = i.ports ?? []
        let states = services.values.map { $0.lowercased() }
        // Same rule as desktop anonStateFrom: a port counts only while no unit state is known.
        let active: String
        if states.contains(where: { $0 == "active" || $0 == "activating" }) {
            active = "active"
        } else if states.isEmpty {
            active = ports.isEmpty ? "unknown" : "active"
        } else {
            active = states.first(where: { !$0.isEmpty && $0 != "active" }) ?? "inactive"
        }
        var m = self
        m.conn = i.conn ?? 0
        m.anon = Anon(active: active, ports: ports, services: services)
        return m
    }

    /// A box with several relays: the given relay's own unit, ports and
    /// connections; a single-relay box's reading as it is.
    func ownOf(_ key: String) -> AgentMetrics {
        guard (instances?.count ?? 0) > 1 else { return self }
        return forInstance(key) ?? self
    }

    /// True when a watched unit that exists on the host belongs to relay software.
    /// Only units that exist are reported (agent.py skips not-found ones), and an
    /// older agent still reports the active ones, so this holds for both.
    var runsRelay: Bool {
        (anon?.services ?? [:]).keys.contains { k in
            ["anon", "anyone", "tor"].contains { k.hasPrefix($0) }
        }
    }

    /// monitor.js / agent.py mantigi: anon "active"/"activating" VEYA dinleyen port varsa saglikli.
    ///
    /// `expectService`: this host is known to run the watched software. When no
    /// watched unit is found at all, that is suspicious on such a host — an older
    /// agent drops a stopped unit instead of reporting it — but on any other server
    /// the service check simply does not apply and must not turn the card yellow.
    /// Without it every ordinary server with the default watch list showed yellow.
    func anonHealthy(expectService: Bool) -> Bool {
        let state = (anon?.active ?? "").lowercased()
        if state == "active" || state == "activating" { return true }
        // BUG FIX (2026-09-22): eskiden burada kosulsuz "port varsa saglikli" deniyordu.
        // Servisi cokmus ama soketi hala acik bir relay YESIL gorunuyordu — masaustu
        // ayni relay'i dogru sekilde kirmizi gosteriyordu (monitor.js anonStateFrom).
        // Dinlenen port ancak servis durumu HIC bilinmiyorken kanit sayilir.
        if !state.isEmpty && state != "unknown" { return false }
        if let ports = anon?.ports, !ports.isEmpty { return true }
        return !expectService
    }

    var anonLabel: String {
        let state = (anon?.active ?? "").lowercased()
        if state.isEmpty || state == "unknown" {
            return (anon?.ports?.isEmpty == false) ? "active" : "—"
        }
        return state
    }
}
