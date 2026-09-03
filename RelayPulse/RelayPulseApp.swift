import SwiftUI

@main
struct RelayPulseApp: App {
    @StateObject private var fleet = FleetStore()
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
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active: fleet.startPolling()
                    case .background, .inactive: fleet.stopPolling()
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
