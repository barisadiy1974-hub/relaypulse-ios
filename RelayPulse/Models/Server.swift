import Foundation

/// A single relay definition exported from desktop RelayPulse ("Export for phone").
/// Same fields and meaning as the Android app's Server.
struct Server: Codable, Identifiable, Hashable {
    var name: String
    var host: String
    var agentPort: Int
    var agentScheme: String
    var agentToken: String
    /// SSH (for tools): user and port. The private key is shared and stored in Keychain.
    var sshUser: String
    var sshPort: Int
    /// Which relay on the host this card is, when one IP runs several anon
    /// instances. "" = the host's only (or first) relay. "2" / "anon2" = the
    /// numbered unit anon2 with /etc/anon/anonrc-2; any other name = anon@NAME
    /// with /etc/anon/instances/NAME/anonrc.
    var instance: String
    /// Relay fingerprint (40 hex) from the desktop export.
    var fingerprint: String
    /// The operator's own label (e.g. the hosting provider), shown on the card.
    var note: String

    var id: String { name }
    /// Port 0 = no agent on this server: it is read over SSH only. An instance
    /// card is read from its box's agent (agent.py v2) or over SSH, never as if
    /// the agent's whole-box answer were its own.
    var usesAgent: Bool { agentPort > 0 && instanceUnit == nil }

    enum CodingKeys: String, CodingKey {
        case name, host, agentPort, agentScheme, agentToken, sshUser, sshPort, instance, fingerprint, note
    }

    init(name: String, host: String, agentPort: Int = 19191,
         agentScheme: String = "https", agentToken: String = "",
         sshUser: String = "root", sshPort: Int = 22,
         instance: String = "", fingerprint: String = "", note: String = "") {
        self.name = name
        self.host = host
        self.agentPort = agentPort
        self.agentScheme = agentScheme.lowercased()
        self.agentToken = agentToken
        self.sshUser = sshUser
        self.sshPort = sshPort
        self.instance = instance
        self.fingerprint = fingerprint
        self.note = note
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
        instance = (try? c.decode(String.self, forKey: .instance)) ?? ""
        fingerprint = ((try? c.decode(String.self, forKey: .fingerprint)) ?? "").uppercased()
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
    }

    // MARK: - Instances (several relays on one box)

    private static let safeUnit = try! NSRegularExpression(pattern: "^[A-Za-z0-9@._-]+$")
    private static let number = try! NSRegularExpression(pattern: "^[0-9]{1,2}$")
    private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    private var cleanInstance: String? {
        let i = instance.trimmingCharacters(in: .whitespaces)
        return (!i.isEmpty && Server.matches(Server.safeUnit, i)) ? i : nil
    }

    /// "2" or "anon2" -> "2"; nil for a named instance or none.
    private var instanceNumber: String? {
        guard let i = cleanInstance else { return nil }
        let n = i.hasPrefix("anon") ? String(i.dropFirst(4)) : i
        return Server.matches(Server.number, n) ? n : nil
    }

    /// The systemd unit of this relay, nil when the card is not an instance.
    var instanceUnit: String? {
        guard let i = cleanInstance else { return nil }
        if let n = instanceNumber { return "anon\(n)" }
        return "anon@\(i)"
    }

    /// The key agent.py v2 reports this relay under: "" first relay, "2" for
    /// anon2 / anonrc-2, NAME for anon@NAME.
    var agentInstanceKey: String { instanceNumber ?? cleanInstance ?? "" }

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
