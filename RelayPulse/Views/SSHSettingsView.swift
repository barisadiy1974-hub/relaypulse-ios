import SwiftUI
import UniformTypeIdentifiers

/// Telefonun SSH anahtarı — Araçlar'ın (nyx/htop/anonrc/Düzelt) çalışması için gerekli.
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
                    LabeledContent("Durum") {
                        Label("Anahtar yüklü", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Theme.ok(scheme))
                    }
                    if let fp = fingerprint {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Parmak izi").font(.caption).foregroundStyle(Theme.muted(scheme))
                            Text(fp).font(.caption2.monospaced()).textSelection(.enabled)
                        }
                    }
                    Button(role: .destructive) {
                        SSHKeyStore.clear(); refresh()
                    } label: { Label("Anahtarı sil", systemImage: "trash") }
                } else {
                    Label("Anahtar yok", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.warn(scheme))
                    Button { showPaste = true } label: { Label("Anahtarı yapıştır", systemImage: "doc.on.clipboard") }
                    Button { showPicker = true } label: { Label("Dosyadan içe aktar", systemImage: "doc.badge.arrow.up") }
                }
            } header: {
                Text("SSH özel anahtarı")
            } footer: {
                Text("Parolasız ed25519 (OpenSSH formatı). Telefona özel anahtar kullan — kaybolursa sadece onu relay'lerden silersin. Keychain'de, sadece bu cihazda saklanır.")
            }

            if hasKey, let first = fleet.servers.first {
                Section("Bağlantı testi") {
                    Button {
                        Task { await test(first) }
                    } label: {
                        HStack {
                            Label("\(first.name) üzerinde dene", systemImage: "bolt.horizontal")
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
                    .navigationTitle("Özel anahtar")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { showPaste = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Kaydet") { save(pasted); pasted = ""; showPaste = false }
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
                else { error = "Dosya okunamadı" }
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
            testResult = r.combined.isEmpty ? "(çıktı yok, çıkış \(r.exitStatus ?? -1))" : r.combined
        } catch {
            testResult = "HATA: \(error.localizedDescription)"
        }
    }
}
