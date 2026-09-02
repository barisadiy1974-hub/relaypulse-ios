import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var fleet: FleetStore
    @Environment(\.dismiss) private var dismiss
    @State private var showPicker = false
    @State private var showClearConfirm = false
    @State private var error: String?

    private let intervals = [30, 60, 120, 300, 600]

    var body: some View {
        NavigationStack {
            Form {
                Section("İzleme") {
                    Picker("Tarama aralığı", selection: $fleet.pollSec) {
                        ForEach(intervals, id: \.self) { s in
                            Text(s < 60 ? "\(s) sn" : "\(s / 60) dk").tag(s)
                        }
                    }
                    Stepper("Kırmızıya geçiş: \(fleet.offlineAfter) hata",
                            value: $fleet.offlineAfter, in: 1...5)
                }

                Section("Filo") {
                    LabeledContent("Sunucu", value: "\(fleet.servers.count)")
                    Button {
                        showPicker = true
                    } label: {
                        Label("Yeni tanım aktar", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label("Filoyu temizle", systemImage: "trash")
                    }
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }

                Section {
                    LabeledContent("Sürüm", value: appVersion)
                } footer: {
                    Text("Yalnızca izleme. Auto-fix, SSH ve yapılandırma değişikliği bu uygulamada yok.")
                }
            }
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showPicker,
                          allowedContentTypes: [.json, .text, .data],
                          allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    do {
                        try fleet.importConfig(from: try Data(contentsOf: url))
                        error = nil
                    } catch { self.error = error.localizedDescription }
                } else if case .failure(let e) = result {
                    error = e.localizedDescription
                }
            }
            .confirmationDialog("Filo tanımı silinsin mi?", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("Sil", role: .destructive) { fleet.clearConfig(); dismiss() }
                Button("Vazgeç", role: .cancel) {}
            }
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
