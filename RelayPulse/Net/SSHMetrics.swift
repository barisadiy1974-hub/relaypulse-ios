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
///
/// An actor on purpose: SSH is far heavier than an HTTPS GET, and the poll loop
/// can hit this from several tasks at once. Serialising keeps a phone from
/// opening a pile of simultaneous SSH connections, and `budget` caps how many a
/// single sweep may spend — without it a network outage would mean 143 SSH
/// attempts, each up to `timeout`, long past the poll interval.
actor SSHMetrics {
    static let shared = SSHMetrics()

    private var budget = 0
    private var criticalBudget = 0

    /// Called once at the start of a sweep. Transient agent losses run ~1% of a
    /// 143-relay fleet, so a handful of attempts covers the real cases; beyond
    /// that the agent is probably down for a reason SSH will not fix either.
    ///
    /// `critical` is a separate reserve for relays whose next failure marks them
    /// offline. Measured 2026-09-07: two relays sat with a wedged agent for four
    /// days, so they consumed the shared budget on *every* sweep alongside a
    /// third with a stale token. Once those three plus a little transient noise
    /// had spent the five attempts, whichever relay came later got no SSH try at
    /// all and went red — while SSH reached it in about one second and its anon
    /// service was healthy the whole time. A relay about to be called offline is
    /// exactly the one worth spending a round trip on, so it no longer queues
    /// behind first-time hiccups.
    func startSweep(budget: Int = 5, critical: Int = 8) {
        self.budget = budget
        self.criticalBudget = critical
    }

    /// Returns nil when the budget is spent, no SSH key is configured, or the
    /// relay does not answer — callers then keep the agent's original error.
    func fetch(_ server: Server, critical: Bool = false) async -> AgentMetrics? {
        guard SSHKeyStore.hasKey else { return nil }
        if critical, criticalBudget > 0 {
            criticalBudget -= 1
        } else if budget > 0 {
            budget -= 1
        } else {
            return nil
        }
        do {
            let r = try await SSHRunner.shared.run(RelayScripts.metrics, on: server, timeout: 12)
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
