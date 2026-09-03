import Foundation

/// Second measurement path for the poll loop: when the HTTPS agent on :19191 is
/// unreachable, ask the relay for the same metrics over SSH.
///
/// The desktop app has had this since the beginning (`monitor.js` falls back to
/// SSH polling when the agent errors), which is why a relay whose agent hiccups
/// stays green there. The phone only ever had the HTTP path, so the same relay
/// turned yellow — the difference the user kept seeing between the two apps.
///
/// The remote side runs the installed agent's own `collect()`, so what comes back
/// is the identical JSON the HTTP endpoint serves and `AgentMetrics` decodes it
/// with no separate parser to keep in sync.
enum SSHMetrics {

    /// Returns nil when no SSH key is configured — callers then keep the agent's
    /// error, exactly as before this fallback existed.
    static func fetch(_ server: Server) async -> AgentMetrics? {
        guard SSHKeyStore.hasKey else { return nil }
        do {
            let r = try await SSHRunner.shared.run(RelayScripts.metrics, on: server, timeout: 20)
            // The script prints one JSON object; anything else (login banners,
            // "python3: not found") is not usable and must not be treated as a
            // successful poll.
            guard let line = r.stdout
                .split(separator: "\n")
                .last(where: { $0.hasPrefix("{") && $0.hasSuffix("}") }),
                  let data = String(line).data(using: .utf8)
            else { return nil }
            return try JSONDecoder().decode(AgentMetrics.self, from: data)
        } catch {
            return nil
        }
    }
}
