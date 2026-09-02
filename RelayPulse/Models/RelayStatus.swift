import Foundation
import SwiftUI

enum RelayState: String {
    case online          // agent OK + anon saglikli
    case warn            // agent OK ama anon inactive / dashboard down
    case stale           // 1 basarisiz poll (gecici)
    case offline         // OFFLINE_AFTER+ ardisik basarisiz
    case unknown         // henuz hic pollanmadi

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
        case .online:  return "Çevrimiçi"
        case .warn:    return "Uyarı"
        case .stale:   return "Sarkıyor"
        case .offline: return "Çevrimdışı"
        case .unknown: return "Bekleniyor"
        }
    }
}

/// Bir relay'in izlemedeki anlik durumu — kart cizimi bunu kullanir.
struct RelayStatus: Identifiable {
    let name: String
    var state: RelayState = .unknown
    var fails: Int = 0
    var lastError: String?
    var lastUpdated: Date?

    // Son basarili olcumden turetilen degerler (stale sirasinda da gorunur kalir).
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
        guard let t = lastUpdated else { return "hic" }
        let s = Int(Date().timeIntervalSince(t))
        if s < 60 { return "\(s)sn" }
        if s < 3600 { return "\(s / 60)dk" }
        return "\(s / 3600)sa"
    }
}
