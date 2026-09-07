import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var fleet: FleetStore
    @Environment(\.colorScheme) private var scheme
    @State private var showPicker = false
    @State private var showAdd = false
    @State private var editing: Server?
    @State private var showClearConfirm = false
    @State private var error: String?
    @EnvironmentObject private var purchases: PurchaseStore

    private let intervals = [30, 60, 120, 300, 600]

    var body: some View {
        Form {
            Section {
                // In demo mode these are sample relays, so the editing controls
                // are not drawn at all rather than merely disabled: the rows set
                // their own foregroundStyle, which overrides the dimming
                // `.disabled` applies, so a disabled row still looked tappable
                // and then did nothing when tapped.
                ForEach(fleet.servers) { s in
                    if fleet.demoMode {
                        relayRow(s, editable: false)
                    } else {
                        Button { editing = s } label: { relayRow(s, editable: true) }
                    }
                }
                .onDelete(perform: fleet.demoMode ? nil : { idx in
                    idx.map { fleet.servers[$0].name }.forEach { fleet.removeServer(named: $0) }
                })
                if !fleet.demoMode {
                    Button { showAdd = true } label: {
                        Label("Add relay", systemImage: "plus")
                    }
                    Button { showPicker = true } label: {
                        Label("Import JSON", systemImage: "square.and.arrow.down")
                    }
                }
            } header: {
                Text("Relays (\(fleet.servers.count))")
            } footer: {
                if fleet.demoMode {
                    Text("These are sample relays. Turn off demo data below to edit your own fleet.")
                }
            }

            Section {
                // A Button, not a Toggle. The Toggle that used to be here never
                // responded to taps on device or in the simulator — verified
                // against the identical `Toggle` in AISettingsView, which flips
                // fine under the same input — so demo mode could be entered but
                // not left from this screen. The buttons that write this same
                // property elsewhere (ImportView, the Relays banner) have always
                // worked, so this uses that shape instead of shipping a dead
                // control. The underlying SwiftUI cause was not isolated.
                if fleet.demoMode {
                    Button("Turn off demo data") { fleet.demoMode = false }
                } else {
                    Button { fleet.demoMode = true } label: {
                        Label("Try demo fleet", systemImage: "eye.fill")
                    }
                }
                Text("Fills the app with a sample fleet so you can look around before adding your own relays. No network connections are made while this is on.")
                    .font(.footnote).foregroundStyle(Theme.muted(scheme))
            } header: {
                Text("Try it out")
            }

            Section("Monitoring") {
                Picker("Poll interval", selection: Binding(
                    get: { fleet.pollSec },
                    set: { fleet.pollSec = $0; fleet.persistSettings() })) {
                    ForEach(intervals, id: \.self) { s in
                        Text(s < 60 ? "\(s) sec" : "\(s / 60) min").tag(s)
                    }
                }
                Stepper("Offline after \(fleet.offlineAfter) failures", value: Binding(
                    get: { fleet.offlineAfter },
                    set: { fleet.offlineAfter = $0; fleet.persistSettings() }), in: 1...5)
            }

            if let error {
                Section { Text(error).foregroundStyle(Theme.err(scheme)).font(.footnote) }
            }

            Section("License") {
                if purchases.isEntitled {
                    LabeledRow("Status", value: "RelayPulse Lifetime")
                } else {
                    LabeledRow("Status", value: "Free — up to \(FleetStore.freeRelayLimit) relays")
                }
                // Nothing left to sell once they own it — offering the button
                // anyway sends an owner into a purchase StoreKit will refuse.
                if !purchases.isEntitled, let product = purchases.product {
                    Button("Purchase RelayPulse Lifetime (\(product.displayPrice))") {
                        Task { await purchases.purchase() }
                    }
                }
                Button("Restore Purchases") {
                    Task { await purchases.restorePurchases() }
                }
                if let message = purchases.errorMessage {
                    Text(message).font(.caption).foregroundStyle(Theme.err(scheme))
                }
            }

            Section {
                // Hidden, not disabled, for the same reason as the relay rows:
                // a disabled row here still drew as a live control.
                if !fleet.demoMode {
                    Button(role: .destructive) { showClearConfirm = true } label: {
                        Label("Remove all relays", systemImage: "trash")
                    }
                }
                LabeledRow("Version", value: appVersion)
            } footer: {
                Text("Monitoring plus on-demand tools. Unattended 24/7 auto-fix stays on desktop RelayPulse — iOS suspends background apps, so a phone cannot do it reliably.")
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showAdd) { ServerEditView(mode: .add) }
        .sheet(item: $editing) { s in ServerEditView(mode: .edit(s)) }
        .fileImporter(isPresented: $showPicker,
                      allowedContentTypes: [.json, .text, .data],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do { try fleet.importConfig(from: try Data(contentsOf: url)); error = nil }
                catch { self.error = error.localizedDescription }
            } else if case .failure(let e) = result {
                error = e.localizedDescription
            }
        }
        .confirmationDialog("Remove every relay definition?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { fleet.clearConfig() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func relayRow(_ s: Server, editable: Bool) -> some View {
        HStack(spacing: 10) {
            Circle().fill(fleet.status(for: s).state.color(scheme)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.name).foregroundStyle(Theme.text(scheme))
                // String(), not interpolation: Text formats a bare
                // Int for the locale, so port 19191 renders as
                // "19 191" in Norwegian and "19.191" in German.
                Text("\(s.host):\(String(s.agentPort))").font(.caption).foregroundStyle(Theme.muted(scheme))
            }
            Spacer()
            if editable {
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
