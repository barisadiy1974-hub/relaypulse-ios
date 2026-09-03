import Foundation
import SwiftUI

/// Activity log for AI / tool runs — mirrors the AI log panel on the Mac.
struct AILogEntry: Codable, Identifiable {
    enum Kind: String, Codable { case analyze, command, test, error }

    var id: UUID = UUID()
    var at: Date = Date()
    var kind: Kind
    var relay: String
    var title: String
    var detail: String
    var ok: Bool

    var icon: String {
        switch kind {
        case .analyze: return "sparkles"
        case .command: return "terminal"
        case .test:    return "bolt.horizontal"
        case .error:   return "exclamationmark.triangle"
        }
    }
}

@MainActor
final class AILog: ObservableObject {
    static let shared = AILog()
    private static let key = "aiLogEntries"
    private static let limit = 200

    @Published private(set) var entries: [AILogEntry] = AILog.load()

    func add(_ e: AILogEntry) {
        entries.insert(e, at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        save()
    }

    func add(kind: AILogEntry.Kind, relay: String, title: String, detail: String, ok: Bool) {
        add(AILogEntry(kind: kind, relay: relay, title: title, detail: detail, ok: ok))
    }

    func clear() { entries = []; save() }

    private func save() {
        if let d = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(d, forKey: Self.key)
        }
    }

    private static func load() -> [AILogEntry] {
        guard let d = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([AILogEntry].self, from: d) else { return [] }
        return list
    }
}
