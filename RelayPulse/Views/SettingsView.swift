import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var fleet: FleetStore
    @Environment(\.colorScheme) private var scheme
    @State private var showPicker = false
    @State private var showAdd = false
    @State private var editing: Server?
    @State private var showClearConfirm = false
    @State private var error: String?

    private let intervals = [30, 60, 120, 300, 600]

    var body: some View {
        Form {
            Section {
                ForEach(fleet.servers) { s in
                    Button {
                        editing = s
                    } label: {
                        HStack(spacing: 10) {
                            Circle().fill(fleet.status(for: s).state.color(scheme)).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.name).foregroundStyle(Theme.text(scheme))
                                Text("\(s.host):\(s.agentPort)").font(.caption).foregroundStyle(Theme.muted(scheme))
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
                .onDelete { idx in
                    idx.map { fleet.servers[$0].name }.forEach { fleet.removeServer(named: $0) }
                }
                Button { showAdd = true } label: {
                    Label("Relay ekle", systemImage: "plus")
                }
                Button { showPicker = true } label: {
                    Label("JSON içe aktar", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("Relay'ler (\(fleet.servers.count))")
            }

            Section("İzleme") {
                Picker("Tarama aralığı", selection: Binding(
                    get: { fleet.pollSec },
                    set: { fleet.pollSec = $0; fleet.persistSettings() })) {
                    ForEach(intervals, id: \.self) { s in
                        Text(s < 60 ? "\(s) sn" : "\(s / 60) dk").tag(s)
                    }
                }
                Stepper("Çevrimdışı eşiği: \(fleet.offlineAfter) hata", value: Binding(
                    get: { fleet.offlineAfter },
                    set: { fleet.offlineAfter = $0; fleet.persistSettings() }), in: 1...5)
            }

            if let error {
                Section { Text(error).foregroundStyle(.red).font(.footnote) }
            }

            Section {
                Button(role: .destructive) { showClearConfirm = true } label: {
                    Label("Tüm relay'leri temizle", systemImage: "trash")
                }
                LabeledContent("Sürüm", value: appVersion)
            } footer: {
                Text("İzleme + Anyone panelleri. 7/24 otomatik auto-fix Mac/Pi RelayPulse'ta kalır — iOS arka planda çalıştıramaz.")
            }
        }
        .navigationTitle("Ayarlar")
        .sheet(isPresented: $showAdd) { ServerEditView(mode: .add) }
        .sheet(item: $editing) { s in ServerEditView(mode: .edit(s)) }
        .fileImporter(isPresented: $showPicker,
                      allowedContentTypes: [.json, .text, .data],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do { try fleet.importConfig(from: try Data(contentsOf: url)); error = nil }
                catch { self.error = error.localizedDescription }
            } else if case .failure(let e) = result {
                error = e.localizedDescription
            }
        }
        .confirmationDialog("Tüm relay tanımları silinsin mi?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Sil", role: .destructive) { fleet.clearConfig() }
            Button("Vazgeç", role: .cancel) {}
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
