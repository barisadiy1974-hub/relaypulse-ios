import SwiftUI

struct RelayCardView: View {
    let server: Server
    let status: RelayStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(status.state.color).frame(width: 10, height: 10)
                Text(server.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                Text(status.state.label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(status.state.color)
                if status.state == .online && !status.anonHealthy {
                    Text("anon")
                        .font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.orange.opacity(0.2), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }

            HStack(spacing: 4) {
                Text(server.host).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(status.ageText).font(.caption2).foregroundStyle(.tertiary)
            }

            if status.state == .offline || status.state == .stale, let err = status.lastError {
                Text(err).font(.caption2).foregroundStyle(.red).lineLimit(2)
            } else {
                HStack(spacing: 14) {
                    metric("anon", status.anonLabel, status.anonHealthy ? .green : .orange)
                    metric("bağ", status.conn.map { "\($0)" } ?? "—", .primary)
                    metric("↓", fmtMbps(status.rxMbps), .primary)
                    metric("↑", fmtMbps(status.txMbps), .primary)
                    metric("cpu", status.cpuPct.map { "\(Int($0))%" } ?? "—", .primary)
                    metric("ram", status.memPct.map { "\(Int($0))%" } ?? "—", .primary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func metric(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(value).font(.caption2.monospacedDigit()).foregroundStyle(color)
        }
    }

    private func fmtMbps(_ v: Double?) -> String {
        guard let v else { return "—" }
        if v < 1 { return String(format: "%.2f", v) }
        if v < 10 { return String(format: "%.1f", v) }
        return "\(Int(v))"
    }
}
