import SwiftUI
import UniformTypeIdentifiers

/// The phone's SSH key — required for Nyx / htop / anonrc / fix commands.
struct SSHSettingsView: View {
    @EnvironmentObject var fleet: FleetStore
    @Environment(\.colorScheme) private var scheme
    @State private var hasKey = SSHKeyStore.hasKey
    @State private var fingerprint = SSHKeyStore.fingerprint
    @State private var showPaste = false
    @State private var showPicker = false
    @State private var pasted = ""
    @State private var error: String?
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        Form {
            Section {
                if hasKey {
                    LabeledContent("Status") {
                        Label("Key loaded", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Theme.ok(scheme))
                    }
                    if let fp = fingerprint {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fingerprint").font(.caption).foregroundStyle(Theme.muted(scheme))
                            Text(fp).font(.caption2.monospaced()).textSelection(.enabled)
                        }
                    }
                    Button(role: .destructive) {
                        SSHKeyStore.clear(); refresh()
                    } label: { Label("Remove key", systemImage: "trash") }
                } else {
                    Label("No key", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.warn(scheme))
                    Button { showPaste = true } label: { Label("Paste key", systemImage: "doc.on.clipboard") }
                    Button { showPicker = true } label: { Label("Import from file", systemImage: "doc.badge.arrow.up") }
                }
            } header: {
                Text("SSH private key")
            } footer: {
                Text("Unencrypted ed25519, OpenSSH format. Use a key dedicated to this phone — if the phone is lost you revoke only that key. Stored in the Keychain, on this device only.")
            }

            if hasKey, let first = fleet.servers.first {
                Section("Connection test") {
                    Button {
                        Task { await test(first) }
                    } label: {
                        HStack {
                            Label("Try on \(first.name)", systemImage: "bolt.horizontal")
                            if testing { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(testing)
                    if let r = testResult {
                        Text(r).font(.caption2.monospaced()).textSelection(.enabled)
                    }
                }
            }

            if let error {
                Section { Text(error).foregroundStyle(Theme.err(scheme)).font(.footnote) }
            }
        }
        .navigationTitle("SSH")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaste) {
            NavigationStack {
                TextEditor(text: $pasted)
                    .font(.system(.caption2, design: .monospaced))
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .padding(8)
                    .navigationTitle("Private key")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showPaste = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") { save(pasted); pasted = ""; showPaste = false }
                                .disabled(pasted.isEmpty)
                        }
                    }
            }
        }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.data, .text],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let u = urls.first {
                let scoped = u.startAccessingSecurityScopedResource()
                defer { if scoped { u.stopAccessingSecurityScopedResource() } }
                if let d = try? Data(contentsOf: u), let s = String(data: d, encoding: .utf8) { save(s) }
                else { error = "Could not read the file" }
            }
        }
    }

    private func save(_ pem: String) {
        do { try SSHKeyStore.store(pem); error = nil; refresh() }
        catch { self.error = error.localizedDescription }
    }

    private func refresh() {
        hasKey = SSHKeyStore.hasKey
        fingerprint = SSHKeyStore.fingerprint
        testResult = nil
    }

    private func test(_ s: Server) async {
        testing = true; testResult = nil
        defer { testing = false }
        do {
            let r = try await SSHRunner.shared.run("hostname; uptime -p", on: s, timeout: 20)
            testResult = r.combined.isEmpty ? "(no output, exit \(r.exitStatus ?? -1))" : r.combined
        } catch {
            testResult = "ERROR: \(error.localizedDescription)"
        }
    }
}
