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
        case .badToken:        return "Agent token hatali (403)"
        case .http(let c):     return "HTTP \(c)"
        case .timeout:         return "Zaman asimi (6s)"
        case .transport(let m): return m
        case .decode(let m):   return "JSON cozulemedi: \(m)"
        case .noURL:           return "Gecersiz adres"
        }
    }
}

/// Her relay'in HTTPS agent'ina dogrudan baglanir. Backend (Pi/Mac) yok.
/// Self-signed sertifikalar kabul edilir; kimlik X-Agent-Token ile dogrulanir.
final class AgentClient: NSObject, URLSessionDelegate {
    static let shared = AgentClient()

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 6
        cfg.timeoutIntervalForResource = 10
        cfg.waitsForConnectivity = false
        cfg.httpMaximumConnectionsPerHost = 4
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    func fetch(_ server: Server) async throws -> AgentMetrics {
        guard let url = server.metricsURL else { throw AgentError.noURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
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

    // MARK: - Self-signed sertifika kabulu
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
