import SwiftUI

/// Relay Config — mirrors the Mac app's "Relay Config" button: pick a relay,
/// then edit its anonrc. The Mac shows a server dropdown above the editor.
struct RelayConfigView: View {
    @EnvironmentObject var fleet: FleetStore
    @State private var selected: String = ""

    private var server: Server? {
        fleet.servers.first { $0.name == selected } ?? fleet.servers.first
    }

    var body: some View {
        Form {
            Section("Server") {
                Picker("Relay", selection: $selected) {
                    ForEach(fleet.servers) { s in Text(s.name).tag(s.name) }
                }
            }

            if let s = server {
                Section {
                    NavigationLink {
                        AnonrcEditorView(server: s)
                    } label: {
                        Label("Edit anonrc on \(s.name)", systemImage: "doc.badge.gearshape")
                    }
                } footer: {
                    Text("Reads and writes /etc/anon/anonrc over SSH. A timestamped backup is kept before every save.")
                }
            } else {
                Section {
                    Text("No relays configured yet.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Relay Config")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if selected.isEmpty { selected = fleet.servers.first?.name ?? "" } }
    }
}
