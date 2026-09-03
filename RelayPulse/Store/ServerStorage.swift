import Foundation

/// Persists the imported fleet definition on-device.
/// Documents/fleet.json — encrypted at rest when the device is locked (FileProtectionType.complete).
enum ServerStorage {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("fleet.json")
    }

    static func load() -> FleetExport? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FleetExport.self, from: data)
    }

    static func save(_ export: FleetExport) {
        guard let data = try? JSONEncoder().encode(export) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}

extension Server: CustomStringConvertible {
    var description: String { "\(name) @ \(host):\(agentPort)" }
}
