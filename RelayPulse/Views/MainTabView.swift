import SwiftUI

/// Root menu. Mirrors the Mac app's sidebar one-for-one, in the same order and
/// with the same labels: Relays · Overview · Wallets · Anyone Dashboard · Nyx ·
/// Htop · Tools · Settings · Relay Config.
///
/// The Mac opens Nyx/Htop in a Terminal window (they are curses programs). iOS
/// has no terminal, so those two run the same checks natively via ToolRunnerView.
struct MainTabView: View {
    @EnvironmentObject var fleet: FleetStore
    @Environment(\.colorScheme) private var scheme

    private static let dashboard = URL(string: "https://dashboard.anyone.io")!

    var body: some View {
        NavStack {
            List {
                Section {
                    row("Relays", "antenna.radiowaves.left.and.right",
                        badge: fleet.servers.count) { DashboardView() }
                    row("Overview", "newspaper") { OverviewView() }
                    row("Wallets", "wallet.bifold") {
                        WebDashboardView(title: "Wallets", url: Self.dashboard)
                    }
                    row("Anyone Dashboard", "chart.bar.doc.horizontal") {
                        WebDashboardView(title: "Anyone Dashboard", url: Self.dashboard)
                    }
                }

                Section {
                    row("Nyx", "chart.xyaxis.line") { ToolRunnerView(kind: .nyx) }
                    row("Htop", "cpu") { ToolRunnerView(kind: .htop) }
                    row("Fleet Health", "waveform.path.ecg") { FleetHealthView() }
                    row("Tools", "wrench.and.screwdriver") { ToolsView() }
                }

                Section {
                    row("Relay Config", "doc.badge.gearshape") { RelayConfigView() }
                    row("Settings", "gearshape") { SettingsView() }
                }
            }
            .navigationTitle("RelayPulse")
            .listStyle(.insetGrouped)
            .hideScrollBackground()
            .background(Theme.bg(scheme))
        }
    }

    @ViewBuilder
    private func row<D: View>(_ title: String, _ icon: String, badge: Int? = nil,
                              @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink { destination() } label: {
            HStack {
                Label(title, systemImage: icon)
                if let badge {
                    Spacer()
                    Text("\(badge)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.muted(scheme))
                }
            }
        }
    }
}
