import ActivityKit
import Foundation

/// Starts / updates / ends the fleet's single Live Activity.
///
/// Called from FleetStore whenever the widget summary is published, so the
/// lock screen follows the same numbers the widget does.
///
/// ponytail: iOS only lets an app *start* an activity from the foreground, so a
/// relay that goes down while the app is closed gets its counter when the app
/// is next opened. Starting it from the outage itself needs an APNs push.
// 16.2, not 16.1: that is where end(_:dismissalPolicy:) lands.
@available(iOS 16.2, *)
enum OutageActivity {
    private static var current: Activity<RelayOutageAttributes>? {
        Activity<RelayOutageAttributes>.activities.first
    }

    static func sync(worstName: String?, offlineCount: Int, since: Date?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        guard offlineCount > 0, let name = worstName else {
            if let a = current { Task { await a.end(nil, dismissalPolicy: .immediate) } }
            return
        }

        let state = RelayOutageAttributes.ContentState(
            worstName: name, offlineCount: offlineCount, since: since ?? Date())

        if let a = current {
            Task { await a.update(using: state) }
        } else {
            // Throws when the app is in the background — expected, see above.
            _ = try? Activity.request(attributes: RelayOutageAttributes(),
                                      contentState: state, pushType: nil)
        }
    }
}
