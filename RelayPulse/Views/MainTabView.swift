import SwiftUI

/// Mac RelayPulse sekmeleri: Röleler · Genel Bakış · Cüzdanlar · Araçlar · Ayarlar.
struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Röleler", systemImage: "antenna.radiowaves.left.and.right") }

            NavigationStack {
                WebDashboardView(title: "Genel Bakış", url: URL(string: "https://www.anyone.io/blog")!)
            }
            .tabItem { Label("Genel Bakış", systemImage: "newspaper") }

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
