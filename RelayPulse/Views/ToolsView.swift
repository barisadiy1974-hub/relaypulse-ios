import SwiftUI

/// Araçlar — Mac'teki Family plan / anonrc / audit karşılığı. Faz 2'de doldurulacak.
struct ToolsView: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                row("anonrc düzenleyici", "Relay'in anonrc dosyasını oku/yaz", "doc.text")
                row("Family plan", "MyFamily satırlarını topla ve dağıt", "person.3")
                row("Denetim (audit)", "Relay kurulum sağlık kontrolü", "checklist")
                row("fail2ban", "Mac IP'sini tüm relay'lerde whitelist'e al", "shield")

                Text("Bu araçlar Mac RelayPulse'ta mevcut. iPhone'a SSH tabanlı olarak Faz 2'de ekleniyor.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted(scheme))
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            .padding(16)
        }
        .background(Theme.bg(scheme))
        .navigationTitle("Araçlar")
    }

    private func row(_ title: String, _ sub: String, _ icon: String) -> some View {
        PanelCard {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Theme.muted(scheme))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text(scheme))
                    Text(sub).font(.system(size: 12)).foregroundStyle(Theme.muted(scheme))
                }
                Spacer()
                Text("yakında").font(.caption2).foregroundStyle(Theme.muted(scheme))
            }
        }
    }
}
