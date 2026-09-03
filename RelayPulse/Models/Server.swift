import Foundation

/// A single relay definition exported from Mac RelayPulse.
/// Source: Mac app "Export to iPhone" → anyone-monitor.json + resolved agentToken.
struct Server: Codable, Identifiable, Hashable {
    var name: String
    var host: String
    var agentPort: Int
    var agentScheme: String
    var agentToken: String
    var wallet: String
    /// SSH (for tools): user and port. The private key is shared and stored in Keychain.
    var sshUser: String
    var sshPort: Int

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, host, agentPort, agentScheme, agentToken, wallet, sshUser, sshPort
    }

    init(name: String, host: String, agentPort: Int = 19191,
         agentScheme: String = "https", agentToken: String = "", wallet: String = "",
         sshUser: String = "root", sshPort: Int = 22) {
        self.name = name
        self.host = host
        self.agentPort = agentPort
        self.agentScheme = agentScheme.lowercased()
        self.agentToken = agentToken
        self.wallet = wallet
        self.sshUser = sshUser
        self.sshPort = sshPort
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        host = try c.decode(String.self, forKey: .host)
        agentPort = (try? c.decode(Int.self, forKey: .agentPort)) ?? 19191
        agentScheme = ((try? c.decode(String.self, forKey: .agentScheme)) ?? "https").lowercased()
        agentToken = (try? c.decode(String.self, forKey: .agentToken)) ?? ""
        wallet = (try? c.decode(String.self, forKey: .wallet)) ?? ""
        sshUser = (try? c.decode(String.self, forKey: .sshUser)) ?? "root"
        sshPort = (try? c.decode(Int.self, forKey: .sshPort)) ?? 22
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

/// Full export file (Mac export output).
struct FleetExport: Codable {
    var exportedAt: Double?
    var pollSec: Int?
    var offlineAfter: Int?
    var servers: [Server]
}
