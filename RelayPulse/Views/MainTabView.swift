import SwiftUI

/// Top-level tabs: Relays · Fleet Health · Wallets · Tools · Settings.
struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Relays", systemImage: "antenna.radiowaves.left.and.right") }

            FleetHealthView()
                .tabItem { Label("Fleet Health", systemImage: "waveform.path.ecg") }

            NavigationStack {
                WebDashboardView(title: "Wallets", url: URL(string: "https://dashboard.anyone.io")!)
            }
            .tabItem { Label("Wallets", systemImage: "wallet.bifold") }

            NavigationStack { ToolsView() }
                .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }

            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
