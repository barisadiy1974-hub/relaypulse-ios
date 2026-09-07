import SwiftUI

/// Add or edit a relay. Lets the app be used standalone, without desktop RelayPulse.
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
    @State private var sshUser = "root"
    @State private var sshPort = "22"
    @State private var showTokenPlain = false
    @State private var error: String?
    @State private var showDelete = false

    private var originalName: String? {
        if case .edit(let s) = mode { return s.name }
        return nil
    }

    var body: some View {
        NavStack {
            Form {
                Section("Relay") {
                    LabeledField("Name", text: $name, placeholder: "relay-01")
                    LabeledField("Host / IP", text: $host, placeholder: "203.0.113.10")
                        .keyboardType(.URL)
                    HStack {
                        Text("Agent port").foregroundStyle(.secondary)
                        Spacer()
                        TextField("19191", text: $port)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                    Picker("Scheme", selection: $scheme) {
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
                    Text("The AGENT_TOKEN of the metrics agent running on the relay. Leave empty if the agent requires no token.")
                }

                Section {
                    LabeledField("SSH user", text: $sshUser, placeholder: "root")
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    HStack {
                        Text("SSH port").foregroundStyle(.secondary)
                        Spacer()
                        TextField("22", text: $sshPort)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                } header: {
                    Text("SSH")
                } footer: {
                    Text("Used by the tools (Nyx, htop, anonrc, fix commands). The private key is shared across relays — set it in Tools › SSH key.")
                }

                Section("Optional") {
                    LabeledField("Wallet", text: $wallet, placeholder: "0x…")
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }

                if case .edit = mode {
                    Section {
                        Button(role: .destructive) { showDelete = true } label: {
                            Label("Delete this relay", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(isEdit ? "Edit relay" : "Add relay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
            .confirmationDialog("Delete \(name)?", isPresented: $showDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let n = originalName { fleet.removeServer(named: n) }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
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
        sshUser = s.sshUser; sshPort = "\(s.sshPort)"
    }

    private func save() {
        let s = Server(
            name: name.trimmingCharacters(in: .whitespaces),
            host: host.trimmingCharacters(in: .whitespaces),
            agentPort: Int(port) ?? 19191,
            agentScheme: scheme,
            agentToken: token.trimmingCharacters(in: .whitespaces),
            wallet: wallet.trimmingCharacters(in: .whitespaces),
            sshUser: sshUser.trimmingCharacters(in: .whitespaces).isEmpty ? "root" : sshUser.trimmingCharacters(in: .whitespaces),
            sshPort: Int(sshPort) ?? 22
        )
        switch mode {
        case .add:
            guard fleet.addServer(s) else {
                error = "A relay with that name already exists."
                return
            }
        case .edit:
            guard fleet.updateServer(s, originalName: originalName ?? s.name) else {
                error = "A relay with that name already exists."
                return
            }
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
