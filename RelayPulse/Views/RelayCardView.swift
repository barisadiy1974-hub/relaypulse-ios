import SwiftUI

/// Mac RelayPulse .card ile aynı görünüm — dikey, iPhone'a uyarlanmış.
struct RelayCardView: View {
    @Environment(\.colorScheme) private var scheme
    let server: Server
    let status: RelayStatus

    private var sc: Color { status.state.color(scheme) }

    var body: some View {
        PanelCard(stateColor: status.state == .online ? Theme.ok(scheme) : sc,
                  dimmed: status.state == .stale || status.state == .offline) {
            VStack(alignment: .leading, spacing: 6) {
                // Başlık satırı
                HStack(spacing: 8) {
                    Circle().fill(sc).frame(width: 9, height: 9)
                    Text(server.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.text(scheme))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(status.state.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(sc)
                    if status.state == .online && !status.anonHealthy {
                        StatePill(text: "anon", color: Theme.warn(scheme))
                    }
                }

                HStack(spacing: 4) {
                    Text(server.host)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted(scheme))
                    Spacer()
                    Text(status.ageText)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted(scheme).opacity(0.7))
                }

                if (status.state == .offline || status.state == .stale), let err = status.lastError {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.err(scheme))
                        .lineLimit(2)
                } else {
                    HStack(spacing: 0) {
                        metric("anon", status.anonLabel, status.anonHealthy ? Theme.ok(scheme) : Theme.warn(scheme))
                        metric("bağ", status.conn.map { "\($0)" } ?? "—", Theme.text(scheme))
                        metric("↓ Mbps", fmt(status.rxMbps), Theme.rx(scheme))
                        metric("↑ Mbps", fmt(status.txMbps), Theme.tx(scheme))
                        metric("cpu", status.cpuPct.map { "\(Int($0))%" } ?? "—", Theme.text(scheme))
                        metric("ram", status.memPct.map { "\(Int($0))%" } ?? "—", Theme.text(scheme))
                    }
                }
            }
        }
    }

    private func metric(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(Theme.muted(scheme))
            Text(value)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fmt(_ v: Double?) -> String {
        guard let v else { return "—" }
        if v < 1 { return String(format: "%.2f", v) }
        if v < 10 { return String(format: "%.1f", v) }
        return "\(Int(v))"
    }
}
