import SwiftUI

/// AI ve araç etkinlik kaydı — Mac'teki AI log listesinin karşılığı.
struct AILogView: View {
    @ObservedObject private var log = AILog.shared
    @Environment(\.colorScheme) private var scheme
    @State private var selected: AILogEntry?

    var body: some View {
        Group {
            if log.entries.isEmpty {
                ContentUnavailableView("Kayıt yok",
                                       systemImage: "text.badge.checkmark",
                                       description: Text("AI teşhisi, komut çalıştırma ve anahtar testleri burada listelenir."))
            } else {
                List {
                    ForEach(log.entries) { e in
                        Button { selected = e } label: { row(e) }
                    }
                }
            }
        }
        .navigationTitle("AI Kaydı")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !log.entries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Temizle", role: .destructive) { log.clear() }
                }
            }
        }
        .sheet(item: $selected) { e in
            ToolOutputSheet(output: ToolOutput(title: e.title, text: e.detail, failed: !e.ok))
        }
    }

    private func row(_ e: AILogEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: e.icon)
                .foregroundStyle(e.ok ? Theme.ok(scheme) : Theme.err(scheme))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(e.relay).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accent(scheme))
                    Text(e.title).font(.system(size: 13)).foregroundStyle(Theme.text(scheme))
                        .lineLimit(1)
                }
                Text(e.detail)
                    .font(.caption2)
                    .foregroundStyle(Theme.muted(scheme))
                    .lineLimit(2)
                Text(e.at.formatted(date: .abbreviated, time: .standard))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted(scheme).opacity(0.7))
            }
        }
        .padding(.vertical, 2)
    }
}
