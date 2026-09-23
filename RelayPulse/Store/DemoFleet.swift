import Foundation

/// Gerçekçi ama tamamen uydurma bir filo.
///
/// İki işi var:
///  1. App Review — inceleyen kişinin SSH ile erişebileceği bir sunucusu veya Mac'i yok.
///     Demo modu olmadan uygulamayı açıp boş bir liste görür ve hiçbir şeyi test
///     edemez; bu Guideline 2.1'den ret sebebidir.
///  2. Mağaza ekran görüntüleri — gerçek filo verisi (sunucu adları, IP'ler)
///     yayınlanmak zorunda kalmaz.
///
/// Üretilen veriler sabit bir tohumla türetilir: her açılışta aynı filo görünür,
/// ama değerler zamanla hafifçe oynar ki ekran canlı hissettirsin.
enum DemoFleet {

    static let bannerText = "Demo data — not a real fleet"

    /// Adlar bilerek jenerik ve rol adı: RelayPulse her sunucu için, tek bir yazılıma özel değil.
    /// Masaüstündeki src/demo-fleet.js ile BİREBİR aynı tutulur.
    private static let blueprint: [(name: String, host: String, state: RelayState)] = [
        ("web-01",             "203.0.113.10",  .online),
        ("web-02",             "203.0.113.11",  .online),
        ("api-01",             "203.0.113.24",  .online),
        ("db-01",              "198.51.100.7",  .online),
        ("db-02",              "198.51.100.8",  .warn),
        ("cache-01",           "198.51.100.42", .online),
        ("worker-01",          "192.0.2.15",    .stale),
        ("worker-02",          "192.0.2.31",    .online),
        ("backup-01",          "192.0.2.77",    .offline),
        ("mail-01",            "203.0.113.90",  .online),
    ]

    static var servers: [Server] {
        blueprint.map {
            Server(name: $0.name, host: $0.host, agentPort: 19191,
                   agentScheme: "https", agentToken: "demo",
                   sshUser: "root", sshPort: 22)
        }
    }

    /// Değerler dakikaya göre yavaşça salınır — ekran donmuş görünmesin.
    static func statuses(at now: Date = Date()) -> [String: RelayStatus] {
        var out: [String: RelayStatus] = [:]
        let tick = Double(Int(now.timeIntervalSince1970) / 20)

        for (i, b) in blueprint.enumerated() {
            let wave = sin(tick / 9 + Double(i)) * 0.5 + 0.5   // 0…1
            var s = RelayStatus(name: b.name)
            s.state = b.state
            s.lastUpdated = now.addingTimeInterval(-Double(8 + i * 3))

            switch b.state {
            case .offline:
                s.fails = 4
                s.lastError = "Connection refused (agent unreachable)"
                s.anonLabel = "—"
                s.anonHealthy = false
                s.lastUpdated = now.addingTimeInterval(-1_450)
            case .stale:
                s.fails = 2
                s.lastError = "Timed out"
                s.anonLabel = "active"
                s.anonHealthy = true
                s.lastUpdated = now.addingTimeInterval(-190)
            case .warn:
                s.anonLabel = "inactive"
                s.anonHealthy = false
            default:
                s.anonLabel = "active"
                s.anonHealthy = true
            }

            if b.state != .offline {
                s.conn = Int(180 + wave * 640) + i * 7
                s.rxMbps = (2.2 + wave * 11).rounded(toPlaces: 1)
                s.txMbps = (1.8 + wave * 9).rounded(toPlaces: 1)
                s.memPct = (44 + wave * 33).rounded(toPlaces: 0)
                s.cpuPct = (6 + wave * 27).rounded(toPlaces: 0)
                s.load = [(0.2 + wave).rounded(toPlaces: 2),
                          (0.3 + wave * 0.8).rounded(toPlaces: 2),
                          (0.4 + wave * 0.5).rounded(toPlaces: 2)]
                s.diskPct = Double(31 + i * 3)
                s.uptime = "\(9 + i) days"
                s.cpuCount = i % 3 == 0 ? 4 : 2
            }
            s.publicIp = b.host
            out[b.name] = s
        }
        return out
    }
}

private extension Double {
    func rounded(toPlaces p: Int) -> Double {
        let m = pow(10.0, Double(p))
        return (self * m).rounded() / m
    }
}
