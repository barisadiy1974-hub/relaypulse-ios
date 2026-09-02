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
                .tint(Color(.sRGB, red: 0.184, green: 0.49, blue: 0.965)) // Mac --accent
                .task {
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

/// `--ssh-selftest` argümanıyla açılınca ilk relay'e SSH atıp sonucu loglar.
/// Tap edemeden SSH yolunu doğrulamak için (simctl launch ... --ssh-selftest).
@MainActor
private func sshSelfTest() async {
    guard let s = ServerStorage.load()?.servers.first else {
        NSLog("SSHSELFTEST: sunucu yok"); return
    }
    NSLog("SSHSELFTEST: anahtar=\(SSHKeyStore.hasKey) hedef=\(s.name) \(s.sshUser)@\(s.host):\(s.sshPort)")
    do {
        let r = try await SSHRunner.shared.run("hostname; systemctl is-active anon", on: s, timeout: 25)
        NSLog("SSHSELFTEST: OK exit=\(r.exitStatus ?? -1) out=\(r.combined.replacingOccurrences(of: "\n", with: " | "))")
    } catch {
        NSLog("SSHSELFTEST: HATA \(error.localizedDescription)")
    }
}

struct RootView: View {
    @EnvironmentObject var fleet: FleetStore

    var body: some View {
        if fleet.isConfigured {
            MainTabView()
        } else {
            ImportView()
        }
    }
}
