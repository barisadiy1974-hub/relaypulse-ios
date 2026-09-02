import SwiftUI

/// Mac RelayPulse sekmeleri: Röleler · Genel Bakış · Cüzdanlar · Araçlar · Ayarlar.
struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Röleler", systemImage: "antenna.radiowaves.left.and.right") }

            FleetHealthView()
                .tabItem { Label("Filo Sağlığı", systemImage: "waveform.path.ecg") }

            NavigationStack {
                WebDashboardView(title: "Cüzdanlar", url: URL(string: "https://dashboard.anyone.io")!)
            }
            .tabItem { Label("Cüzdanlar", systemImage: "wallet.bifold") }

            NavigationStack { ToolsView() }
                .tabItem { Label("Araçlar", systemImage: "wrench.and.screwdriver") }

            NavigationStack { SettingsView() }
                .tabItem { Label("Ayarlar", systemImage: "gearshape") }
        }
    }
}
