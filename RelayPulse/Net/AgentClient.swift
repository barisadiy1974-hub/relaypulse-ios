import Foundation

enum AgentError: LocalizedError {
    case badToken
    case http(Int)
    case timeout
    case transport(String)
    case decode(String)
    case noURL

    var errorDescription: String? {
        switch self {
        // Says what to do, not just what happened. A 403 here is always the same
        // situation — the relay's agent token was regenerated (a reinstall, or a
        // fleet exported to this phone before the token changed) and the stored
        // copy is stale. "Agent token rejected (403)" left operators hunting a
        // fault on a machine that was working perfectly.
        case .badToken:        return "Agent token rejected — the relay's token changed; update it in this relay's settings"
        case .http(let c):     return "HTTP \(c)"
        case .timeout:         return "Timed out"
        case .transport(let m): return m
        case .decode(let m):   return "Could not decode JSON: \(m)"
        case .noURL:           return "Invalid address"
        }
    }
}

/// Connects straight to each relay's HTTPS agent — no backend in between.
/// Self-signed certificates are accepted; identity is proven by X-Agent-Token.
final class AgentClient: NSObject, URLSessionDelegate {
    static let shared = AgentClient()

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        // The agent speaks plain HTTP/1.1 (Python http.server + a TLS socket) —
        // no HTTP/3. The QUIC race is disabled per request (see
        // req.assumesHTTP3Capable in fetchOnce); otherwise, sweeping a large
        // fleet in parallel wastes time on QUIC attempts that fall back to TCP,
        // which showed up as spurious "stale" cards.
        cfg.timeoutIntervalForRequest = 12
        cfg.timeoutIntervalForResource = 16
        cfg.waitsForConnectivity = false
        cfg.httpMaximumConnectionsPerHost = 2
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    /// Retries once on a transient failure (timeout / connection), mirroring the
    /// desktop SSH retry. Permanent failures (403, HTTP 4xx/5xx, parse) are not retried.
    func fetch(_ server: Server) async throws -> AgentMetrics {
        do {
            return try await fetchOnce(server)
        } catch let e as AgentError {
            switch e {
            case .timeout, .transport:
                try? await Task.sleep(nanoseconds: 400_000_000)
                return try await fetchOnce(server)
            default:
                throw e
            }
        }
    }

    private func fetchOnce(_ server: Server) async throws -> AgentMetrics {
        guard let url = server.metricsURL else { throw AgentError.noURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.assumesHTTP3Capable = false
        if !server.agentToken.isEmpty {
            req.setValue(server.agentToken, forHTTPHeaderField: "X-Agent-Token")
        }
        req.setValue("RelayPulse-iOS", forHTTPHeaderField: "User-Agent")

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await session.data(for: req)
        } catch let e as URLError {
            if e.code == .timedOut { throw AgentError.timeout }
            throw AgentError.transport(e.localizedDescription)
        } catch {
            throw AgentError.transport(error.localizedDescription)
        }

        if let http = resp as? HTTPURLResponse {
            if http.statusCode == 403 { throw AgentError.badToken }
            guard (200..<300).contains(http.statusCode) else { throw AgentError.http(http.statusCode) }
        }

        do {
            return try JSONDecoder().decode(AgentMetrics.self, from: data)
        } catch {
            throw AgentError.decode(error.localizedDescription)
        }
    }

    // MARK: - Accept self-signed certificates
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
