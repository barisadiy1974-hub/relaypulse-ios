import AppIntents
import Foundation

extension Notification.Name {
    /// Posted right after a repair request is stored, so an app that is already
    /// running acts on it now. scenePhase alone is not enough: a warm app can
    /// reach .active before the intent has run, and the request would then sit
    /// until the next launch — the tap looking like it did nothing.
    static let relayFixRequested = Notification.Name("relayFixRequested")
}

/// The widget's "Onar" button. Records the request (PendingFix) and opens the
/// app, which runs the first auto-fix command over SSH.
@available(iOS 17.0, *)
struct FixRelayIntent: AppIntent {
    static var title: LocalizedStringResource = "Relay'i onar"
    /// The fix is an SSH session; it belongs in the app, not the extension.
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Relay")
    var relay: String

    init() {}
    init(relay: String) { self.relay = relay }

    func perform() async throws -> some IntentResult {
        PendingFix(relay: relay).save()
        NotificationCenter.default.post(name: .relayFixRequested, object: nil)
        return .result()
    }
}
