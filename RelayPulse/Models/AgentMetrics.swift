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

    /// monitor.js / agent.py mantigi: anon "active"/"activating" VEYA dinleyen port varsa saglikli.
    var anonHealthy: Bool {
        let state = (anon?.active ?? "").lowercased()
        if state == "active" || state == "activating" { return true }
        // BUG FIX (2026-09-22): eskiden burada kosulsuz "port varsa saglikli" deniyordu.
        // Servisi cokmus ama soketi hala acik bir relay YESIL gorunuyordu — masaustu
        // ayni relay'i dogru sekilde kirmizi gosteriyordu (monitor.js anonStateFrom).
        // Dinlenen port ancak servis durumu HIC bilinmiyorken kanit sayilir.
        if !state.isEmpty && state != "unknown" { return false }
        if let ports = anon?.ports, !ports.isEmpty { return true }
        return false
    }

    var anonLabel: String {
        let state = (anon?.active ?? "").lowercased()
        if state.isEmpty { return anonHealthy ? "active" : "unknown" }
        return state
    }
}
