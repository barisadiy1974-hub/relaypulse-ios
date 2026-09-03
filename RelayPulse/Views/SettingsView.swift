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
    @State private var licenseState = LicenseStore.state
    @State private var licenseInput = ""
    @State private var licenseError = ""

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
                switch licenseState {
                case .licensed(let serial):
                    LabeledRow("Status", value: "Licensed")
                    LabeledRow("Serial", value: serial.uppercased())
                    Button(role: .destructive) {
                        LicenseStore.deactivate()
                        licenseState = LicenseStore.state
                    } label: { Text("Remove license") }
                case .trial(let daysLeft):
                    LabeledRow("Status", value: "\(daysLeft) day\(daysLeft == 1 ? "" : "s") left in trial")
                    TextField("RP1-XXXXXXXX-…", text: $licenseInput)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                    if !licenseError.isEmpty {
                        Text(licenseError).font(.caption).foregroundStyle(Theme.err(scheme))
                    }
                    Button("Activate license") { activateLicense() }
                        .disabled(licenseInput.trimmingCharacters(in: .whitespaces).isEmpty)
                case .expired:
                    LabeledRow("Status", value: "Trial expired")
                    TextField("RP1-XXXXXXXX-…", text: $licenseInput)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                    if !licenseError.isEmpty {
                        Text(licenseError).font(.caption).foregroundStyle(Theme.err(scheme))
                    }
                    Button("Activate license") { activateLicense() }
                        .disabled(licenseInput.trimmingCharacters(in: .whitespaces).isEmpty)
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

    private func activateLicense() {
        let k = licenseInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if LicenseStore.activate(k) {
            licenseState = LicenseStore.state
            licenseInput = ""
            licenseError = ""
        } else {
            licenseError = "Invalid license key."
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
