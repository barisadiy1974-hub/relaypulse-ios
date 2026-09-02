import SwiftUI

@main
struct RelayPulseApp: App {
    @StateObject private var fleet = FleetStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(fleet)
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        fleet.startPolling()
                    case .background, .inactive:
                        fleet.stopPolling()
                    @unknown default:
                        break
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var fleet: FleetStore

    var body: some View {
        Group {
            if fleet.isConfigured {
                DashboardView()
            } else {
                ImportView()
            }
        }
    }
}
