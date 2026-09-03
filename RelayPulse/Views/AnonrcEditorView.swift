import SwiftUI

/// Read / edit / write anonrc, the equivalent of the desktop config editor.
/// A timestamped backup is taken on the relay before anything is written.
struct AnonrcEditorView: View {
    @Environment(\.colorScheme) private var scheme
    let server: Server

    @State private var text = ""
    @State private var original = ""
    @State private var path = ""
    @State private var loading = true
    @State private var saving = false
    @State private var status: String?
    @State private var failed = false
    @State private var showSaveConfirm = false

    private var dirty: Bool { text != original && !original.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            if loading {
                ProgressView("Reading anonrc…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextEditor(text: $text)
                    .font(.system(size: 12, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(6)
            }
            if let status {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(failed ? Theme.err(scheme) : Theme.ok(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.bar)
            }
        }
        .background(Theme.bg(scheme))
        .navigationTitle(path.isEmpty ? "anonrc" : (path as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if saving { ProgressView() }
                else { Button("Save") { showSaveConfirm = true }.disabled(!dirty) }
            }
        }
        .confirmationDialog("Write anonrc and restart the anon service?",
                            isPresented: $showSaveConfirm, titleVisibility: .visible) {
            Button("Write and restart", role: .destructive) { Task { await save(restart: true) } }
            Button("Write only") { Task { await save(restart: false) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(path) on \(server.name). A timestamped backup is taken first.")
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let r = try await SSHRunner.shared.run(RelayScripts.readAnonrc, on: server, timeout: 25)
            let parts = r.stdout.components(separatedBy: "\n---\n")
            path = parts.first?.replacingOccurrences(of: "PATH=", with: "").trimmingCharacters(in: .whitespaces) ?? ""
            text = parts.count > 1 ? parts[1] : r.combined
            original = text
            if path.isEmpty { status = "anonrc not found"; failed = true }
        } catch {
            text = ""; status = error.localizedDescription; failed = true
        }
    }

    private func save(restart: Bool) async {
        guard !path.isEmpty else { return }
        saving = true
        defer { saving = false }
        // Quoted heredoc delimiter so the shell never expands the file contents.
        let marker = "RPEOF_\(UInt32.random(in: 100000...999999))"
        var cmd = """
        cp \(path) \(path).bak-$(date +%Y%m%d-%H%M%S) 2>/dev/null
        cat > \(path) <<'\(marker)'
        \(text)
        \(marker)
        echo "wrote $(wc -l < \(path)) lines"
        """
        if restart {
            cmd += "\nfor svc in anon anon@default anyone anyone-relay; do systemctl cat \"$svc\" >/dev/null 2>&1 && systemctl restart \"$svc\" && echo \"restarted: $svc\" && break; done"
        }
        do {
            let r = try await SSHRunner.shared.run(cmd, on: server, timeout: 40)
            status = r.combined
            failed = (r.exitStatus ?? 0) != 0
            if !failed { original = text }
        } catch {
            status = error.localizedDescription; failed = true
        }
    }
}
