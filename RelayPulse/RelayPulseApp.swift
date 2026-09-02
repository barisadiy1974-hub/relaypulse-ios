import SwiftUI

@main
struct RelayPulseApp: App {
    @StateObject private var fleet = FleetStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(fleet)
                .tint(Color(.sRGB, red: 0.184, green: 0.49, blue: 0.965)) // Mac --accent
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
