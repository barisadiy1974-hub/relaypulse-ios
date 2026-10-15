import Foundation

/// agent.py v2 reports every relay of its box (2026-10-11). The cards of one
/// box (anon@default, anon2 … anon16) share one agent answer for a few seconds,
/// so a 16-relay box costs one request per sweep instead of 16 SSH logins.
/// Same idea as desktop fetchAgentShared and Android Monitor.boxReading.
actor BoxReadings {
    static let shared = BoxReadings()

    private struct Entry {
        let at: Date
        let task: Task<AgentMetrics, Error>
    }
    private var entries: [String: Entry] = [:]
    /// Long enough for every card of one box in one sweep, short enough that
    /// the 10 s rate reading after a first sweep gets a fresh answer.
    private let shareFor: TimeInterval = 8

    func reading(_ src: Server) async throws -> AgentMetrics {
        let key = "\(src.host.trimmingCharacters(in: .whitespaces))|\(src.agentPort)|\(src.agentToken)"
        if let e = entries[key], Date().timeIntervalSince(e.at) < shareFor {
            return try await e.task.value
        }
        let task = Task { try await AgentClient.shared.fetch(src) }
        entries[key] = Entry(at: Date(), task: task)
        do {
            return try await task.value
        } catch {
            // A failed answer is not shared: the next card asks again.
            if entries[key]?.task == task { entries[key] = nil }
            throw error
        }
    }
}
