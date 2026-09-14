import ActivityKit
import Foundation

/// Lock-screen / Dynamic Island state for an outage.
///
/// One activity for the whole fleet, not one per relay: the point is a single
/// live counter saying how long the fleet has been degraded, and iOS shows only
/// one activity in the Dynamic Island anyway.
@available(iOS 16.1, *)
struct RelayOutageAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Worst relay's name — the one the operator will go and look at.
        var worstName: String
        /// How many relays are red right now.
        var offlineCount: Int
        /// Last time the worst relay actually answered; the view counts up from
        /// here with `.timer`, so the clock runs without any further updates.
        var since: Date
    }
}
