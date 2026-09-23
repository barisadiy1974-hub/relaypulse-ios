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
    @State private var publicLine = SSHKeyStore.publicKeyLine
    @State private var copied = false
    @State private var showInstall = false

    var body: some View {
        Form {
            Section {
                if hasKey {
                    LabeledRow("Status") {
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
                    Button {
                        do { try SSHKeyStore.generate(); error = nil; refresh() }
                        catch { self.error = error.localizedDescription }
                    } label: { Label("Create a key on this phone", systemImage: "key.fill") }
                    Button { showPaste = true } label: { Label("Paste key", systemImage: "doc.on.clipboard") }
                    Button { showPicker = true } label: { Label("Import from file", systemImage: "doc.badge.arrow.up") }
                    // Both buttons above assume a key already exists somewhere. It
                    // usually does not, and that is where setup stalls.
                    NavigationLink {
                        HelpView()
                    } label: {
                        Label("I do not have a key yet", systemImage: "questionmark.circle")
                    }
                }
            } header: {
                Text("SSH private key")
            } footer: {
                Text("Unencrypted ed25519, OpenSSH format. Use a key dedicated to this phone — if the phone is lost you revoke only that key. Stored in the Keychain, on this device only.")
            }

            if hasKey, let line = publicLine {
                Section {
                    Text(line)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                    Button {
                        UIPasteboard.general.string = line
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy public key",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    if !fleet.servers.isEmpty {
                        Button { showInstall = true } label: {
                            Label("Install on a server with its password", systemImage: "arrow.up.doc")
                        }
                    }
                } header: {
                    Text("Public key")
                } footer: {
                    Text("This line goes into ~/.ssh/authorized_keys on each server. Paste it there yourself, or let the app put it there using the server's root password once — the password is used for that single login and never stored.")
                }
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
            NavStack {
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
        .sheet(isPresented: $showInstall) { InstallKeyView() }
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
        publicLine = SSHKeyStore.publicKeyLine
        copied = false
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

/// Puts this phone's public key on one relay using that relay's password, then
/// proves the key works by logging in again with the key alone.
private struct InstallKeyView: View {
    @EnvironmentObject var fleet: FleetStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var serverID = ""
    @State private var password = ""
    @State private var running = false
    @State private var result: String?
    @State private var ok = false

    var body: some View {
        NavStack {
            Form {
                Section {
                    Picker("Server", selection: $serverID) {
                        ForEach(fleet.servers) { s in Text(s.name).tag(s.id) }
                    }
                    SecureField("Root password", text: $password)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } footer: {
                    Text("Used for this one login to add the key, then forgotten. It is never saved on the phone. Servers that have password login switched off will refuse it — that is the safer setup, and there you paste the public key yourself.")
                }

                Section {
                    Button {
                        Task { await install() }
                    } label: {
                        HStack {
                            Label("Install key", systemImage: "arrow.up.doc")
                            if running { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(running || password.isEmpty || serverID.isEmpty)
                }

                if let result {
                    Section {
                        Text(result)
                            .font(.footnote)
                            .foregroundStyle(ok ? Theme.ok(scheme) : Theme.err(scheme))
                    }
                }
            }
            .navigationTitle("Install key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(ok ? "Done" : "Cancel") { dismiss() } }
            }
            .onAppear { if serverID.isEmpty { serverID = fleet.servers.first?.id ?? "" } }
            .onDisappear { password = "" }
        }
    }

    private func install() async {
        guard let server = fleet.servers.first(where: { $0.id == serverID }),
              let command = SSHKeyStore.installCommand else { return }
        running = true; result = nil; ok = false
        let pw = password
        password = ""                       // gone from the UI before the network call
        defer { running = false }

        do {
            let r = try await SSHRunner.shared.run(command, on: server, password: pw, timeout: 20)
            guard r.stdout.contains("KEY_INSTALLED") else {
                result = "The server did not confirm the key was added.\n\(r.combined)"
                return
            }
        } catch SSHError.auth {
            result = "Password refused, or \(server.name) does not allow password login. If password login is off, copy the public key and add it to ~/.ssh/authorized_keys yourself."
            return
        } catch {
            result = error.localizedDescription
            return
        }

        // The whole point is that the key works on its own from now on.
        do {
            _ = try await SSHRunner.shared.run("true", on: server, timeout: 15)
            ok = true
            result = "Key installed on \(server.name), and a login with the key alone works. The password is no longer needed."
        } catch {
            result = "The key was added, but logging in with it failed: \(error.localizedDescription)"
        }
    }
}
