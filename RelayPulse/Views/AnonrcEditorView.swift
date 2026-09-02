import SwiftUI

/// anonrc oku / düzenle / yaz — Mac'teki anonrc düzenleyicinin karşılığı.
/// Yazmadan önce relay'de zaman damgalı yedek alınır.
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
                ProgressView("anonrc okunuyor…").frame(maxWidth: .infinity, maxHeight: .infinity)
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
            ToolbarItem(placement: .topBarTrailing) {
                if saving { ProgressView() }
                else { Button("Kaydet") { showSaveConfirm = true }.disabled(!dirty) }
            }
        }
        .confirmationDialog("anonrc yazılıp anon servisi yeniden başlatılsın mı?",
                            isPresented: $showSaveConfirm, titleVisibility: .visible) {
            Button("Yaz ve yeniden başlat", role: .destructive) { Task { await save(restart: true) } }
            Button("Sadece yaz") { Task { await save(restart: false) } }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("\(server.name) üzerinde \(path). Önce zaman damgalı yedek alınır.")
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        let cmd = """
        for p in /etc/anon/anonrc /etc/anon/anonrc-* /etc/anon/instances/*/anonrc /usr/local/etc/anon/anonrc /etc/tor/torrc; do
          [ -f "$p" ] && { echo "PATH=$p"; echo '---'; cat "$p"; exit 0; }
        done
        echo "PATH="; echo '---'; echo "(anonrc bulunamadi)"
        """
        do {
            let r = try await SSHRunner.shared.run(cmd, on: server, timeout: 25)
            let parts = r.stdout.components(separatedBy: "\n---\n")
            path = parts.first?.replacingOccurrences(of: "PATH=", with: "").trimmingCharacters(in: .whitespaces) ?? ""
            text = parts.count > 1 ? parts[1] : r.combined
            original = text
            if path.isEmpty { status = "anonrc bulunamadı"; failed = true }
        } catch {
            text = ""; status = error.localizedDescription; failed = true
        }
    }

    private func save(restart: Bool) async {
        guard !path.isEmpty else { return }
        saving = true
        defer { saving = false }
        // Heredoc ile yaz — içerik kabuk tarafından yorumlanmasın diye tırnaklı sınırlayıcı.
        let marker = "RPEOF_\(UInt32.random(in: 100000...999999))"
        var cmd = """
        cp \(path) \(path).bak-$(date +%Y%m%d-%H%M%S) 2>/dev/null
        cat > \(path) <<'\(marker)'
        \(text)
        \(marker)
        echo "yazildi: $(wc -l < \(path)) satir"
        """
        if restart {
            cmd += "\nfor svc in anon anon@default anyone anyone-relay; do systemctl cat \"$svc\" >/dev/null 2>&1 && systemctl restart \"$svc\" && echo \"restart: $svc\" && break; done"
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
