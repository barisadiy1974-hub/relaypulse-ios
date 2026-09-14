import Foundation

/// A repair the operator asked for from the widget, waiting for the app.
///
/// The widget's button cannot run the fix itself: repairing a relay means an
/// SSH session with the fleet's private key, and a widget extension has neither
/// the key nor the memory budget for it. So the button records the request and
/// opens the app, which runs it immediately — one tap, no navigation.
struct PendingFix: Codable {
    static let key = "pendingFix"
    /// Requests older than this are dropped: the app may not be opened until
    /// much later, and restarting a relay service that has been fine for an
    /// hour is not what the tap meant.
    static let maxAge: TimeInterval = 10 * 60

    var relay: String
    var at = Date()

    func save() {
        guard let d = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: FleetSummary.appGroup)?.set(d, forKey: Self.key)
    }

    /// Reads and clears — a request is acted on once.
    static func take() -> PendingFix? {
        let store = UserDefaults(suiteName: FleetSummary.appGroup)
        guard let d = store?.data(forKey: key) else { return nil }
        store?.removeObject(forKey: key)
        guard let f = try? JSONDecoder().decode(PendingFix.self, from: d),
              Date().timeIntervalSince(f.at) < maxAge else { return nil }
        return f
    }
}
