import SwiftUI

/// AI / Auto-Fix settings. On iPhone there is no unattended auto-fix —
/// the key and command list power the manual "Diagnose with AI" action.
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

    var body: some View {
        Form {
            Section("Provider") {
                Picker("AI provider", selection: $ai.aiProvider) {
                    Text("OpenAI (gpt-4o-mini)").tag("openai")
                    Text("Claude (haiku)").tag("claude")
                }
                Toggle("Diagnosis only (dry-run)", isOn: $ai.dryRun)
            }

            Section {
                // Only the selected provider's field is shown — two boxes made it
                // unclear which key belonged where.
                if ai.aiProvider == "claude" {
                    secureRow("Claude API key", text: $ai.claudeKey, reveal: $showClaude, placeholder: "sk-ant-…")
                    HStack {
                        Text("Workspace ID").foregroundStyle(.secondary)
                        Spacer()
                        TextField("optional", text: $ai.claudeWorkspaceId)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.callout)
                    }
                } else {
                    secureRow("OpenAI API key", text: $ai.openaiKey, reveal: $showOpenAI, placeholder: "sk-…")
                }

                Button {
                    Task { await testKey() }
                } label: {
                    HStack {
                        Label("Test key", systemImage: "bolt.horizontal")
                        if testing { Spacer(); ProgressView() }
                    }
                }
                .disabled(testing)

                // Catch a key pasted into the wrong provider before it hits the API.
                if let other = ai.keyBelongsToOtherProvider {
                    let otherLabel = other == "claude" ? "Claude" : "OpenAI"
                    VStack(alignment: .leading, spacing: 6) {
                        Label("This is a \(otherLabel) key in the \(ai.providerLabel) field.",
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
                            Label("Switch to \(otherLabel) and move the key", systemImage: "arrow.left.arrow.right")
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
                Text("\(ai.providerLabel) key · \(ai.modelLabel)")
            } footer: {
                Text(ai.aiProvider == "claude"
                     ? "Stored in the Keychain. Workspace ID is only needed for workspace-scoped (identity-linked) keys — leave it empty otherwise. \"Test key\" sends one tiny request."
                     : "Stored in the Keychain. \"Test key\" sends one tiny request so you know immediately whether the key works.")
            }

            Section {
                NavigationLink { AILogView() } label: {
                    HStack {
                        Label("Activity log / errors", systemImage: "list.bullet.rectangle")
                        Spacer()
                        Text("\(AILog.shared.entries.count)").foregroundStyle(Theme.muted(scheme))
                    }
                }
            } footer: {
                Text("Diagnoses, commands that ran, and errors are kept here.")
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
                Button { showAddCmd = true } label: { Label("Add command", systemImage: "plus") }
                Button("Restore defaults") { ai.resetCommands() }
                    .foregroundStyle(Theme.err(scheme))
            } header: {
                Text("Fix commands (\(ai.commands.count))")
            } footer: {
                Text("Same seven defaults as desktop RelayPulse. \"Diagnose with AI\" picks from this list.")
            }
        }
        .navigationTitle("AI / Auto-Fix")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { c in
            CommandEditor(command: c) { updated in
                if let i = ai.commands.firstIndex(where: { $0.id == c.id }) { ai.commands[i] = updated }
            }
        }
        .sheet(isPresented: $showAddCmd) {
            CommandEditor(command: FixCommand(id: (ai.commands.map(\.id).max() ?? 0) + 1, name: "", command: "")) { new in
                ai.commands.append(new)
            }
        }
    }

    private func testKey() async {
        testing = true; testResult = nil
        defer { testing = false }
        guard ai.hasKey else {
            testOK = false
            testResult = "✗ \(ai.providerLabel) key is empty — enter it above."
            return
        }
        if let other = ai.keyBelongsToOtherProvider {
            testOK = false
            let otherLabel = other == "claude" ? "Claude" : "OpenAI"
            testResult = "✗ That is a \(otherLabel) key (starts with \(other == "claude" ? "sk-ant-" : "sk-")) but the provider is \(ai.providerLabel). Use the switch button above."
            return
        }
        do {
            let info = try await AIFixer.testKey(provider: ai.aiProvider, key: ai.activeKey,
                                                 workspaceId: ai.claudeWorkspaceId)
            testOK = true
            testResult = "✓ Key works — \(info)"
            AILog.shared.add(kind: .test, relay: "—", title: "API key test", detail: info, ok: true)
        } catch {
            testOK = false
            let raw = error.localizedDescription
            if raw.contains("anthropic-workspace-id") {
                testResult = "✗ This key is scoped to a workspace. Enter its ID in \"Workspace ID\" above (Anthropic Console › Settings › Workspaces) — it looks like wrkspc_…, not the workspace name."
            } else if raw.contains("credit balance") || raw.contains("insufficient") {
                testResult = "✗ No credit on the account — add balance in the provider console."
            } else {
                testResult = "✗ \(raw)"
            }
            AILog.shared.add(kind: .test, relay: "—", title: "API key test", detail: raw, ok: false)
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
        NavStack {
            Form {
                TextField("Name", text: $command.name)
                Section("Command (bash, runs as root on the relay)") {
                    TextEditor(text: $command.command)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 120)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Command")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(command); dismiss() }
                        .disabled(command.name.isEmpty || command.command.isEmpty)
                }
            }
        }
    }
}
