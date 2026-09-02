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
    @State private var testing = false
    @State private var testResult: String?
    @State private var testOK = false

    private func testKey() async {
        testing = true; testResult = nil
        defer { testing = false }
        guard ai.hasKey else {
            testOK = false
            testResult = "✗ \(ai.providerLabel) anahtarı boş — yukarıdaki alana gir"
            return
        }
        if let other = ai.keyBelongsToOtherProvider {
            testOK = false
            let otherLabel = other == "claude" ? "Claude" : "OpenAI"
            testResult = "✗ Girdiğin anahtar \(otherLabel) anahtarı (\(other == "claude" ? "sk-ant-" : "sk-") ile başlıyor) ama sağlayıcı \(ai.providerLabel). Yukarıdaki düğmeyle \(otherLabel)'a geç."
            return
        }
        do {
            let info = try await AIFixer.testKey(provider: ai.aiProvider, key: ai.activeKey)
            testOK = true
            testResult = "✓ Anahtar geçerli — \(info)"
            AILog.shared.add(kind: .test, relay: "—", title: "API anahtarı testi", detail: info, ok: true)
        } catch {
            testOK = false
            testResult = "✗ \(error.localizedDescription)"
            AILog.shared.add(kind: .test, relay: "—", title: "API anahtarı testi",
                             detail: error.localizedDescription, ok: false)
        }
    }

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
                // Sadece secili saglayicinin anahtari gosterilir — iki kutu
                // "hangisi nereye" karisikligi yaratiyordu.
                if ai.aiProvider == "claude" {
                    secureRow("Claude API Key", text: $ai.claudeKey, reveal: $showClaude, placeholder: "sk-ant-…")
                } else {
                    secureRow("OpenAI API Key", text: $ai.openaiKey, reveal: $showOpenAI, placeholder: "sk-…")
                }
                Button {
                    Task { await testKey() }
                } label: {
                    HStack {
                        Label("Anahtarı test et", systemImage: "bolt.horizontal")
                        if testing { Spacer(); ProgressView() }
                    }
                }
                .disabled(testing)

                // Yanlis kutuya yapistirilan anahtari API'ye gitmeden yakala.
                if let other = ai.keyBelongsToOtherProvider {
                    let otherLabel = other == "claude" ? "Claude" : "OpenAI"
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Bu bir \(otherLabel) anahtarı, \(ai.providerLabel) kutusunda.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.warn(scheme))
                        Button {
                            let k = ai.activeKey
                            if other == "claude" { ai.openaiKey = ""; ai.claudeKey = k }
                            else { ai.claudeKey = ""; ai.openaiKey = k }
                            ai.aiProvider = other
                            testResult = nil
                        } label: {
                            Label("\(otherLabel)'a geç ve anahtarı taşı", systemImage: "arrow.left.arrow.right")
                                .font(.footnote.weight(.semibold))
                        }
                    }
                }

                if let t = testResult {
                    Text(t)
                        .font(.caption2)
                        .foregroundStyle(testOK ? Theme.ok(scheme) : Theme.err(scheme))
                        .textSelection(.enabled)
                }
            } header: {
                Text("\(ai.providerLabel) anahtarı · \(ai.modelLabel)")
            } footer: {
                Text("Yukarıda seçili sağlayıcının anahtarı. Keychain'de saklanır. \"Test et\" küçük bir istek atar — anahtar geçerli mi hemen görürsün. Sağlayıcıyı değiştirirsen o sağlayıcının kutusu gelir.")
            }

            Section {
                NavigationLink { AILogView() } label: {
                    HStack {
                        Label("AI kaydı / hatalar", systemImage: "list.bullet.rectangle")
                        Spacer()
                        Text("\(AILog.shared.entries.count)").foregroundStyle(Theme.muted(scheme))
                    }
                }
            } footer: {
                Text("Yapılan teşhisler, çalıştırılan komutlar ve hatalar burada tutulur.")
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
