import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @EnvironmentObject var fleet: FleetStore
    @State private var showPicker = false
    @State private var pasteText = ""
    @State private var showPaste = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text("Filo tanimini iceri aktar")
                    .font(.title2.bold())
                Text("Mac RelayPulse → Ayarlar → \u{201C}iPhone'a Aktar\u{201D} ile olusan JSON dosyasini buraya al.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                VStack(spacing: 12) {
                    Button {
                        showPicker = true
                    } label: {
                        Label("Dosya sec", systemImage: "doc.badge.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        showPaste = true
                    } label: {
                        Label("JSON yapistir", systemImage: "doc.on.clipboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 40)

                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                Spacer()
            }
            .navigationTitle("RelayPulse")
            .fileImporter(isPresented: $showPicker,
                          allowedContentTypes: [.json, .text, .data],
                          allowsMultipleSelection: false) { result in
                handle(result)
            }
            .sheet(isPresented: $showPaste) {
                PasteSheet(text: $pasteText) { raw in
                    apply(Data(raw.utf8))
                }
            }
        }
    }

    private func handle(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let e):
            error = e.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do { apply(try Data(contentsOf: url)) }
            catch { self.error = error.localizedDescription }
        }
    }

    private func apply(_ data: Data) {
        do {
            try fleet.importConfig(from: data)
            error = nil
        } catch {
            self.error = "Aktarim basarisiz: \(error.localizedDescription)"
        }
    }
}

private struct PasteSheet: View {
    @Binding var text: String
    var onSubmit: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.system(.footnote, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(8)
                .navigationTitle("JSON yapistir")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Vazgec") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Aktar") { onSubmit(text); dismiss() }
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
    }
}
