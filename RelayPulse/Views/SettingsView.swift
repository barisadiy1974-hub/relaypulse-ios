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
                ForEach(fleet.servers) { s in
                    Button {
                        editing = s
                    } label: {
                        HStack(spacing: 10) {
                            Circle().fill(fleet.status(for: s).state.color(scheme)).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.name).foregroundStyle(Theme.text(scheme))
                                Text("\(s.host):\(s.agentPort)").font(.caption).foregroundStyle(Theme.muted(scheme))
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
                .onDelete { idx in
                    idx.map { fleet.servers[$0].name }.forEach { fleet.removeServer(named: $0) }
                }
                Button { showAdd = true } label: {
                    Label("Add relay", systemImage: "plus")
                }
                Button { showPicker = true } label: {
                    Label("Import JSON", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("Relays (\(fleet.servers.count))")
            }

            Section {
                Toggle("Demo data", isOn: $fleet.demoMode)
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
                } else if purchases.trialDaysLeft > 0 {
                    LabeledRow("Status", value: "\(purchases.trialDaysLeft) day\(purchases.trialDaysLeft == 1 ? "" : "s") left in trial")
                } else {
                    LabeledRow("Status", value: "Trial expired")
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
                Button(role: .destructive) { showClearConfirm = true } label: {
                    Label("Remove all relays", systemImage: "trash")
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

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
