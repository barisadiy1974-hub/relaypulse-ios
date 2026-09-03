import Foundation
import SwiftUI

enum RelayState: String {
    case online          // agent OK + anon healthy
    case warn            // agent OK but anon inactive / dashboard down
    case stale           // 1 failed poll (transient)
    case offline         // OFFLINE_AFTER+ consecutive failures
    case unknown         // never polled yet

    func color(_ s: ColorScheme) -> Color {
        switch self {
        case .online:  return Theme.ok(s)
        case .warn:    return Theme.warn(s)
        case .stale:   return Theme.warn(s)
        case .offline: return Theme.err(s)
        case .unknown: return Theme.muted(s)
        }
    }

    var label: String {
        switch self {
        case .online:  return "Online"
        case .warn:    return "Warning"
        case .stale:   return "Stale"
        case .offline: return "Offline"
        case .unknown: return "Pending"
        }
    }
}

/// A relay's current monitored state — what the card renders.
struct RelayStatus: Identifiable {
    let name: String
    var state: RelayState = .unknown
    var fails: Int = 0
    var lastError: String?
    var lastUpdated: Date?

    // Derived from the last successful poll; stays visible while stale.
    var anonLabel: String = "—"
    var anonHealthy: Bool = false
    var conn: Int?
    var rxMbps: Double?
    var txMbps: Double?
    var memPct: Double?
    var cpuPct: Double?
    var load: [Double]?
    var diskPct: Double?
    var uptime: String?
    var publicIp: String?
    var cpuCount: Int?

    var id: String { name }

    var ageText: String {
        guard let t = lastUpdated else { return "never" }
        let s = Int(Date().timeIntervalSince(t))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h"
    }
}
