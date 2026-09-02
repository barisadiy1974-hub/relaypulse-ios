import SwiftUI

/// AI / Auto-Fix ayarları — Mac'teki "AI Auto-Fix" bölümünün iPhone karşılığı.
/// iPhone'da 7/24 sessiz otomatik YOK; anahtar + komutlar elle "Düzelt" için kullanılır.
struct AISettingsView: View {
    @EnvironmentObject var ai: AppSettings
    @Environment(\.colorScheme) private var scheme
    @State private var showOpenAI = false
    @State private var showClaude = false
    @State private var editing: FixCommand?
    @State private var showAddCmd = false

    var body: some View {
        Form {
            Section("Sağlayıcı") {
                Picker("AI sağlayıcı", selection: $ai.aiProvider) {
                    Text("OpenAI (gpt-4o-mini)").tag("openai")
                    Text("Claude (haiku)").tag("claude")
                }
                Toggle("Sadece teşhis (dry-run)", isOn: $ai.dryRun)
            }

            Section {
                secureRow("OpenAI API Key", text: $ai.openaiKey, reveal: $showOpenAI, placeholder: "sk-…")
                secureRow("Claude API Key", text: $ai.claudeKey, reveal: $showClaude, placeholder: "sk-ant-…")
            } header: {
                Text("Anahtarlar")
            } footer: {
                Text("Keychain'de saklanır. Anahtar yoksa teşhis çalışmaz; düzeltme komutlarını yine elle çalıştırabilirsin.")
            }

            Section {
                ForEach(ai.commands) { c in
                    Button { editing = c } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name).foregroundStyle(Theme.text(scheme))
                            Text(c.command).font(.caption2.monospaced())
                                .foregroundStyle(Theme.muted(scheme)).lineLimit(1)
                        }
                    }
                }
                .onDelete { ai.commands.remove(atOffsets: $0) }
                Button { showAddCmd = true } label: { Label("Komut ekle", systemImage: "plus") }
                Button("Varsayılanlara döndür") { ai.resetCommands() }
                    .foregroundStyle(Theme.err(scheme))
            } header: {
                Text("Düzeltme komutları (\(ai.commands.count))")
            } footer: {
                Text("Mac RelayPulse ile aynı 7 varsayılan. Kırmızı relay'de \"Düzelt\" bu listeden seçer.")
            }
        }
        .navigationTitle("AI / Auto-Fix")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { c in CommandEditor(command: c) { updated in
            if let i = ai.commands.firstIndex(where: { $0.id == c.id }) { ai.commands[i] = updated }
        }}
        .sheet(isPresented: $showAddCmd) {
            CommandEditor(command: FixCommand(id: (ai.commands.map(\.id).max() ?? 0) + 1, name: "", command: "")) { new in
                ai.commands.append(new)
            }
        }
    }

    @ViewBuilder
    private func secureRow(_ label: String, text: Binding<String>, reveal: Binding<Bool>, placeholder: String) -> some View {
        HStack {
            if reveal.wrappedValue {
                TextField(placeholder, text: text).autocorrectionDisabled().textInputAutocapitalization(.never)
            } else {
                SecureField(placeholder, text: text)
            }
            Button { reveal.wrappedValue.toggle() } label: {
                Image(systemName: reveal.wrappedValue ? "eye.slash" : "eye")
            }.buttonStyle(.borderless)
        }
    }
}

private struct CommandEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var command: FixCommand
    var onSave: (FixCommand) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Ad", text: $command.name)
                Section("Komut (bash, relay'de root olarak çalışır)") {
                    TextEditor(text: $command.command)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 120)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Komut")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { onSave(command); dismiss() }
                        .disabled(command.name.isEmpty || command.command.isEmpty)
                }
            }
        }
    }
}
