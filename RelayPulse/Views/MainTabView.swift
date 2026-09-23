import SwiftUI

/// Root menu. Mirrors the Mac app's sidebar: Relays · Nyx · Htop · Fleet Health ·
/// Tools · Relay Config · Settings.
///
/// The Mac opens Nyx/Htop in a Terminal window (they are curses programs). iOS
/// has no terminal, so those two run the same checks natively via ToolRunnerView.
struct MainTabView: View {
    @EnvironmentObject var fleet: FleetStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavStack {
            List {
                Section {
                    row("Servers", "server.rack",
                        badge: fleet.servers.count) { DashboardView() }
                }

                Section {
                    // Relay tools only for fleets that actually run relay software.
                    if fleet.hasRelays {
                        row("Nyx", "chart.xyaxis.line") { ToolRunnerView(kind: .nyx) }
                    }
                    row("Htop", "cpu") { ToolRunnerView(kind: .htop) }
                    row("Fleet Health", "waveform.path.ecg") { FleetHealthView() }
                    row("Tools", "wrench.and.screwdriver") { ToolsView() }
                }

                Section {
                    if fleet.hasRelays {
                        row("Relay Config", "doc.badge.gearshape") { RelayConfigView() }
                    }
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
