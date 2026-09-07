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
                    // No "Wallets" row. It opened dashboard.anyone.io — the same
                    // URL as the row below it — so it was a second door to one
                    // page, and the name promised a wallet the app does not
                    // have: nothing here holds keys, moves funds or reads a
                    // balance. On iOS a payout address is only stored and
                    // displayed.
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
