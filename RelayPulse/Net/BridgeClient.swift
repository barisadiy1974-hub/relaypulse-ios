import Foundation

/// Read-only client for the Mac RelayPulse bridge. Auto-Fix commands never pass
/// through this client; the Mac runs them locally and exposes only results.
enum BridgeClient {
    struct Payload: Decodable {
        var relays: [Relay]
    }

    struct Relay: Decodable {
        var name: String
        var state: String
        var issue: String?
        var anon: String?
        var error: String?
        var rxMbps: Double?
        var txMbps: Double?
        var conn: Double?
        var memPct: Double?
        var cpuPct: Double?
        var uptimeSec: Double?
        var publicIp: String?
        var ts: Double?
    }

    enum BridgeError: LocalizedError {
        case invalidURL
        case http(Int)
        case decode(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid Mac bridge address"
            case .http(let code): return "Mac bridge HTTP \(code)"
            case .decode(let message): return "Mac bridge data error: \(message)"
            }
        }
    }

    static func fetch(_ bridge: MacBridge) async throws -> Payload {
        guard let base = URL(string: "http://\(bridge.host):\(bridge.port)"),
              let host = base.host else { throw BridgeError.invalidURL }
        var c = URLComponents()
        c.scheme = base.scheme; c.host = host; c.port = bridge.port; c.path = "/api/snapshot"
        guard let url = c.url else { throw BridgeError.invalidURL }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(bridge.token)", forHTTPHeaderField: "Authorization")
        req.setValue("RelayPulse-iOS", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw BridgeError.http(http.statusCode)
        }
        do { return try JSONDecoder().decode(Payload.self, from: data) }
        catch { throw BridgeError.decode(error.localizedDescription) }
    }
}
