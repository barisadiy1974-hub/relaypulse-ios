import SwiftUI

/// Bir araç/komut çıktısı.
struct ToolOutput: Identifiable {
    let id = UUID()
    let title: String
    let text: String
    let failed: Bool
}

/// Çıktıyı tam ekran, seçilebilir ve paylaşılabilir gösterir.
struct ToolOutputSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    let output: ToolOutput

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                Text(output.text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(output.failed ? Theme.err(scheme) : Theme.text(scheme))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Theme.bg(scheme))
            .navigationTitle(output.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Kapat") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: output.text) { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
    }
}
