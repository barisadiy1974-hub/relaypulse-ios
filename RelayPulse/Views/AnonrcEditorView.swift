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
        // Written to a sibling temp file and moved into place, never straight
        // over the live anonrc. `cat > anonrc` truncates the file *before* it
        // writes, so on a full disk — the very failure this app exists to catch
        // — the old redirect emptied the config while the ignored `cp` had also
        // failed to leave a backup, and "Write and restart" then brought anon up
        // on nothing. `set -e` stops at the first failure, the line count
        // catches a short write, and `cp -p` seeds the temp file so the final
        // `mv` keeps the original's mode and owner.
        // wc -l counts newlines and the heredoc adds a final one, which is
        // exactly what this split counts.
        let expectedLines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        var cmd = """
        set -e
        cp -p "\(path)" "\(path).bak-$(date +%Y%m%d-%H%M%S)"
        cp -p "\(path)" "\(path).rp-new"
        cat > "\(path).rp-new" <<'\(marker)'
        \(text)
        \(marker)
        n=$(wc -l < "\(path).rp-new")
        [ "$n" -eq \(expectedLines) ] || { rm -f "\(path).rp-new"; echo "short write ($n of \(expectedLines) lines) — anonrc left untouched"; exit 1; }
        mv "\(path).rp-new" "\(path)"
        echo "wrote $n lines"
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
