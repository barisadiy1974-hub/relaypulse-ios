import Foundation

/// Mac RelayPulse'tan disari aktarilan tek bir relay tanimi.
/// Kaynak: Mac app "iPhone'a Aktar" -> anyone-monitor.json + cozulmus agentToken.
struct Server: Codable, Identifiable, Hashable {
    var name: String
    var host: String
    var agentPort: Int
    var agentScheme: String
    var agentToken: String
    var wallet: String

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, host, agentPort, agentScheme, agentToken, wallet
    }

    init(name: String, host: String, agentPort: Int = 19191,
         agentScheme: String = "https", agentToken: String = "", wallet: String = "") {
        self.name = name
        self.host = host
        self.agentPort = agentPort
        self.agentScheme = agentScheme.lowercased()
        self.agentToken = agentToken
        self.wallet = wallet
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        host = try c.decode(String.self, forKey: .host)
        agentPort = (try? c.decode(Int.self, forKey: .agentPort)) ?? 19191
        agentScheme = ((try? c.decode(String.self, forKey: .agentScheme)) ?? "https").lowercased()
        agentToken = (try? c.decode(String.self, forKey: .agentToken)) ?? ""
        wallet = (try? c.decode(String.self, forKey: .wallet)) ?? ""
    }

    var metricsURL: URL? {
        var comps = URLComponents()
        comps.scheme = agentScheme.isEmpty ? "https" : agentScheme
        comps.host = host
        comps.port = agentPort
        comps.path = "/metrics"
        return comps.url
    }
}

/// Aktarim dosyasinin tamami (Mac export ciktisi).
struct FleetExport: Codable {
    var exportedAt: Double?
    var pollSec: Int?
    var offlineAfter: Int?
    var servers: [Server]
}
