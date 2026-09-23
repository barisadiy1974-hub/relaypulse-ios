import Foundation

/// A single relay definition exported from Mac RelayPulse.
/// Source: Mac app "Export to iPhone" → anyone-monitor.json + resolved agentToken.
struct Server: Codable, Identifiable, Hashable {
    var name: String
    var host: String
    var agentPort: Int
    var agentScheme: String
    var agentToken: String
    /// SSH (for tools): user and port. The private key is shared and stored in Keychain.
    var sshUser: String
    var sshPort: Int

    var id: String { name }
    /// Port 0 = no agent on this server: it is read over SSH only.
    var usesAgent: Bool { agentPort > 0 }

    enum CodingKeys: String, CodingKey {
        case name, host, agentPort, agentScheme, agentToken, sshUser, sshPort
    }

    init(name: String, host: String, agentPort: Int = 19191,
         agentScheme: String = "https", agentToken: String = "",
         sshUser: String = "root", sshPort: Int = 22) {
        self.name = name
        self.host = host
        self.agentPort = agentPort
        self.agentScheme = agentScheme.lowercased()
        self.agentToken = agentToken
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

/// Optional Mac RelayPulse bridge. When present, the Mac is the monitoring and
/// Auto-Fix authority; the phone only reads its authenticated snapshots.
struct MacBridge: Codable, Hashable {
    var host: String
    var port: Int = 8787
    var token: String

    private enum CodingKeys: String, CodingKey { case host, hosts, port, token }

    init(host: String, port: Int = 8787, token: String) {
        self.host = host
        self.port = port
        self.token = token
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        host = try c.decodeIfPresent(String.self, forKey: .host)
            ?? c.decodeIfPresent([String].self, forKey: .hosts)?.first
            ?? ""
        guard !host.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .host, in: c,
                                                    debugDescription: "Mac bridge host is missing")
        }
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 8787
        token = try c.decode(String.self, forKey: .token)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(host, forKey: .host)
        try c.encode(port, forKey: .port)
        try c.encode(token, forKey: .token)
    }
}

/// Full export file (Mac export output).
struct FleetExport: Codable {
    var exportedAt: Double?
    var pollSec: Int?
    var offlineAfter: Int?
    var bridge: MacBridge?
    var servers: [Server]
}
