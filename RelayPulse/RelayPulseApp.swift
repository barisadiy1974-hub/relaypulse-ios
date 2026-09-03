import BackgroundTasks
import SwiftUI

private enum RelayBackgroundRefresh {
    static let identifier = "com.baris.relaypulse.refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// Registers the background refresh task the pre-SwiftUI way.
///
/// `.backgroundTask(.appRefresh:)` would be tidier but it is iOS 16+, and
/// `SceneBuilder` does not accept an `if #available` around a scene modifier, so
/// there is no way to apply it conditionally. Registering here works from iOS 13
/// on — one code path, and the iPhone 7 on iOS 15 still gets background refresh.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: RelayBackgroundRefresh.identifier,
            using: nil
        ) { task in
            let work = Task { @MainActor in
                await FleetStore.shared.refreshInBackground()
                RelayBackgroundRefresh.schedule()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
        return true
    }
}

@main
struct RelayPulseApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // Shared instance so the background task handler can reach the same store.
    @StateObject private var fleet = FleetStore.shared
    @StateObject private var ai = AppSettings()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(fleet)
                .environmentObject(ai)
                .tint(Color(.sRGB, red: 0.184, green: 0.49, blue: 0.965)) // matches Mac --accent
                .task {
                    _ = LicenseStore.firstLaunch  // record first-launch date if not set
                    SSHKeyStore.importSeedFileIfPresent()
                    ai.importSeedKeyIfPresent()
                    if ProcessInfo.processInfo.arguments.contains("--ssh-selftest") {
                        await sshSelfTest()
                    }
                }
                // Single-parameter form: the (old, new) closure is iOS 17+ and the
                // app supports iOS 15 so an iPhone 7 can run it.
                .onChange(of: scenePhase) { phase in
                    switch phase {
                    case .active: fleet.startPolling()
                    case .background:
                        fleet.stopPolling()
                        RelayBackgroundRefresh.schedule()
                    case .inactive:
                        break
                    @unknown default: break
                    }
                }
        }
    }
}

/// Launched with `--ssh-selftest`: SSHs into the first relay and logs the result.
/// Useful for verifying the SSH path without tapping the UI (simctl launch … --ssh-selftest).
@MainActor
private func sshSelfTest() async {
    guard let s = ServerStorage.load()?.servers.first else {
        NSLog("SSHSELFTEST: no servers"); return
    }
    NSLog("SSHSELFTEST: hasKey=\(SSHKeyStore.hasKey) target=\(s.name) \(s.sshUser)@\(s.host):\(s.sshPort)")
    do {
        let r = try await SSHRunner.shared.run("hostname; systemctl is-active anon", on: s, timeout: 25)
        NSLog("SSHSELFTEST: OK exit=\(r.exitStatus ?? -1) out=\(r.combined.replacingOccurrences(of: "\n", with: " | "))")
    } catch {
        NSLog("SSHSELFTEST: ERROR \(error.localizedDescription)")
    }
}

struct RootView: View {
    @EnvironmentObject var fleet: FleetStore
    @State private var licenseState = LicenseStore.state

    var body: some View {
        Group {
            switch licenseState {
            case .expired:
                TrialExpiredView()
                    .onAppear { licenseState = LicenseStore.state }
            case .licensed, .trial:
                if fleet.isConfigured {
                    MainTabView()
                } else {
                    ImportView()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            licenseState = LicenseStore.state
        }
    }
}
