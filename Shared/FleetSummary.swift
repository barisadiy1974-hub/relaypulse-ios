import Foundation

/// App -> widget'a aktarilan tek satirlik filo ozeti. App Group UserDefaults
/// uzerinden paylasilir; widget SSH/agent'a hic dokunmaz.
struct FleetSummary: Codable {
    static let appGroup = "group.com.baris.relaypulse"
    static let key = "fleetSummary"

    var total = 0
    var online = 0
    var warn = 0
    var stale = 0
    var offline = 0
    var worstName: String?
    var worstError: String?
    var worstSince: Date?
    var updated = Date()
    /// Son yayinlardaki cevrimici sayilari (en fazla 48); widget'taki egri icin.
    var history: [Int] = []

    static func load() -> FleetSummary? {
        guard let d = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(FleetSummary.self, from: d)
    }

    func save() {
        guard let d = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.appGroup)?.set(d, forKey: Self.key)
    }
}
