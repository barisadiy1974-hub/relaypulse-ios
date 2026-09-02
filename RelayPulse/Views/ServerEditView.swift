import SwiftUI

/// Relay ekle / düzenle. Standalone kullanım: Mac RelayPulse olmadan da relay girilebilir.
struct ServerEditView: View {
    enum Mode: Equatable {
        case add
        case edit(Server)
    }

    @EnvironmentObject var fleet: FleetStore
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var name = ""
    @State private var host = ""
    @State private var port = "19191"
    @State private var scheme = "https"
    @State private var token = ""
    @State private var wallet = ""
    @State private var showTokenPlain = false
    @State private var error: String?
    @State private var showDelete = false

    private var originalName: String? {
        if case .edit(let s) = mode { return s.name }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Relay") {
                    LabeledField("Ad", text: $name, placeholder: "Barisfreak1")
                    LabeledField("Host / IP", text: $host, placeholder: "143.20.134.161")
                        .keyboardType(.URL)
                    HStack {
                        Text("Port").foregroundStyle(.secondary)
                        Spacer()
                        TextField("19191", text: $port)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                    Picker("Şema", selection: $scheme) {
                        Text("HTTPS").tag("https")
                        Text("HTTP").tag("http")
                    }
                }

                Section {
                    HStack {
                        if showTokenPlain {
                            TextField("Agent token", text: $token)
                                .autocorrectionDisabled().textInputAutocapitalization(.never)
                        } else {
                            SecureField("Agent token", text: $token)
                        }
                        Button { showTokenPlain.toggle() } label: {
                            Image(systemName: showTokenPlain ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                } header: {
                    Text("Agent token")
                } footer: {
                    Text("Relay'deki agent servisinin AGENT_TOKEN değeri (/opt/anyone-agent). Boşsa agent token istemiyordur.")
                }

                Section("İsteğe bağlı") {
                    LabeledField("Cüzdan", text: $wallet, placeholder: "0x…")
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }

                if case .edit = mode {
                    Section {
                        Button(role: .destructive) { showDelete = true } label: {
                            Label("Bu relay'i sil", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(isEdit ? "Relay Düzenle" : "Relay Ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }.disabled(!canSave)
                }
            }
            .confirmationDialog("\(name) silinsin mi?", isPresented: $showDelete, titleVisibility: .visible) {
                Button("Sil", role: .destructive) {
                    if let n = originalName { fleet.removeServer(named: n) }
                    dismiss()
                }
                Button("Vazgeç", role: .cancel) {}
            }
            .onAppear(perform: load)
        }
    }

    private var isEdit: Bool { if case .edit = mode { return true }; return false }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !host.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func load() {
        guard case .edit(let s) = mode else { return }
        name = s.name; host = s.host; port = "\(s.agentPort)"
        scheme = s.agentScheme.isEmpty ? "https" : s.agentScheme
        token = s.agentToken; wallet = s.wallet
    }

    private func save() {
        let s = Server(
            name: name.trimmingCharacters(in: .whitespaces),
            host: host.trimmingCharacters(in: .whitespaces),
            agentPort: Int(port) ?? 19191,
            agentScheme: scheme,
            agentToken: token.trimmingCharacters(in: .whitespaces),
            wallet: wallet.trimmingCharacters(in: .whitespaces)
        )
        switch mode {
        case .add:
            guard fleet.addServer(s) else {
                error = "Bu adda relay zaten var."
                return
            }
        case .edit:
            fleet.updateServer(s, originalName: originalName ?? s.name)
        }
        dismiss()
    }
}

private struct LabeledField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    init(_ label: String, text: Binding<String>, placeholder: String = "") {
        self.label = label; self._text = text; self.placeholder = placeholder
    }
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            TextField(placeholder, text: $text).multilineTextAlignment(.trailing)
        }
    }
}
