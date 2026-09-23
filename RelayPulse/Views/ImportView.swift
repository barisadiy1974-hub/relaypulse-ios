import SwiftUI
import UniformTypeIdentifiers

/// First launch, no relays yet. Add one by hand or import a fleet JSON.
struct ImportView: View {
    @EnvironmentObject var fleet: FleetStore
    @Environment(\.colorScheme) private var scheme
    @State private var showPicker = false
    @State private var showAdd = false
    @State private var pasteText = ""
    @State private var showPaste = false
    @State private var error: String?

    var body: some View {
        NavStack {
            VStack(spacing: 22) {
                Spacer()
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 54))
                    .foregroundStyle(Theme.accent(scheme))
                Text("RelayPulse")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Theme.text(scheme))
                Text("Monitor every Linux server you run. Add a server to get started.")
                    .font(.callout)
                    .foregroundStyle(Theme.muted(scheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                VStack(spacing: 12) {
                    Button {
                        showAdd = true
                    } label: {
                        Label("Add server", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        showPicker = true
                    } label: {
                        Label("Import fleet JSON", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button("Paste JSON") { showPaste = true }
                        .font(.footnote)

                    // Without this the demo fleet is unreachable on a fresh
                    // install: the only other way in is Settings, and Settings
                    // lives behind MainTabView, which needs a server already
                    // configured. Someone with no relays yet -- App Review
                    // included -- would have nothing to look at.
                    Button {
                        fleet.demoMode = true
                    } label: {
                        Label("Try Demo Fleet", systemImage: "eye.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 8)

                    Text("Fills the app with a sample fleet so you can look around before adding your own servers.")
                        .font(.caption)
                        .foregroundStyle(Theme.muted(scheme))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 36)

                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                        .multilineTextAlignment(.center).padding(.horizontal, 32)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg(scheme))
            .sheet(isPresented: $showAdd) { ServerEditView(mode: .add) }
            .fileImporter(isPresented: $showPicker,
                          allowedContentTypes: [.json, .text, .data],
                          allowsMultipleSelection: false) { result in
                handleFile(result)
            }
            .sheet(isPresented: $showPaste) {
                PasteSheet(text: $pasteText) { raw in apply(Data(raw.utf8)) }
            }
        }
    }

    private func handleFile(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let e): error = e.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do { apply(try Data(contentsOf: url)) }
            catch { self.error = error.localizedDescription }
        }
    }

    private func apply(_ data: Data) {
        do { try fleet.importConfig(from: data); error = nil }
        catch { self.error = "Import failed: \(error.localizedDescription)" }
    }
}

private struct PasteSheet: View {
    @Binding var text: String
    var onSubmit: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavStack {
            TextEditor(text: $text)
                .font(.system(.footnote, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(8)
                .navigationTitle("Paste JSON")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import") { onSubmit(text); dismiss() }
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
    }
}
