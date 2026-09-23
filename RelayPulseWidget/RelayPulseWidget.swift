import AppIntents
import SwiftUI
import WidgetKit

struct Entry: TimelineEntry {
    let date: Date
    let s: FleetSummary?
}

struct Provider: TimelineProvider {
    func placeholder(in: Context) -> Entry {
        Entry(date: Date(), s: FleetSummary(total: 143, online: 141, warn: 1, stale: 0, offline: 1,
                                            worstName: "web-01", worstError: "No SSH",
                                            worstSince: Date().addingTimeInterval(-1560),
                                            history: [140, 141, 141, 139, 142, 143, 143, 141, 141]))
    }
    func getSnapshot(in ctx: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), s: FleetSummary.load() ?? placeholder(in: ctx).s))
    }
    func getTimeline(in: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let e = Entry(date: Date(), s: FleetSummary.load())
        completion(Timeline(entries: [e], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

private let ok = Color(red: 0.24, green: 0.85, blue: 0.55)
private let warnC = Color(red: 0.98, green: 0.75, blue: 0.20)
private let err = Color(red: 0.95, green: 0.38, blue: 0.38)
private let dim = Color.white.opacity(0.55)
private let track = Color.white.opacity(0.12)

private func age(_ d: Date?) -> String {
    guard let d else { return "" }
    let m = Int(Date().timeIntervalSince(d) / 60)
    if m < 1 { return "şimdi" }
    return m < 60 ? "\(m) dk" : "\(m / 60) sa"
}

struct Ring: View {
    let s: FleetSummary
    var size: CGFloat = 60
    var body: some View {
        let t = max(s.total, 1)
        let onl = Double(s.online) / Double(t)
        let bad = Double(s.offline) / Double(t)
        ZStack {
            Circle().stroke(track, lineWidth: size * 0.13)
            Circle().trim(from: 0, to: onl).stroke(ok, style: .init(lineWidth: size * 0.13, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if bad > 0 {
                Circle().trim(from: onl, to: min(1, onl + max(bad, 0.02)))
                    .stroke(err, style: .init(lineWidth: size * 0.13, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Text("\(Int((onl * 100).rounded()))%")
                .font(.system(size: size * 0.28, weight: .semibold)).foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

struct Sparkline: View {
    let values: [Int]

    private func paths(_ size: CGSize) -> (line: Path, fill: Path, last: CGPoint) {
        let v = values.count >= 2 ? values : [values.first ?? 0, values.first ?? 0]
        let lo = Double(v.min() ?? 0), hi = Double(v.max() ?? 1)
        let span = max(hi - lo, 2)
        let pts = v.enumerated().map { i, y in
            CGPoint(x: size.width * CGFloat(i) / CGFloat(v.count - 1),
                    y: size.height * (1 - CGFloat((Double(y) - lo) / span)) * 0.85 + size.height * 0.08)
        }
        var line = Path(); line.move(to: pts[0]); pts.dropFirst().forEach { line.addLine(to: $0) }
        var fill = line
        fill.addLine(to: CGPoint(x: size.width, y: size.height))
        fill.addLine(to: CGPoint(x: 0, y: size.height)); fill.closeSubpath()
        return (line, fill, pts[pts.count - 1])
    }

    var body: some View {
        GeometryReader { g in
            let p = paths(g.size)
            ZStack {
                p.fill.fill(LinearGradient(colors: [ok.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                p.line.stroke(ok, style: .init(lineWidth: 2, lineCap: .round, lineJoin: .round))
                Circle().fill(ok).frame(width: 6, height: 6).position(p.last)
            }
        }
    }
}

struct WidgetView: View {
    @Environment(\.widgetFamily) var family
    let e: Entry

    var body: some View {
        if let s = e.s {
            switch family {
            case .accessoryInline: inline(s)
            case .accessoryCircular: circular(s)
            case .accessoryRectangular: rect(s)
            case .systemMedium: medium(s)
            default: small(s)
            }
        } else {
            Text("RelayPulse'u bir kez aç").font(.caption).foregroundStyle(dim)
        }
    }

    func header(_ s: FleetSummary) -> some View {
        HStack {
            Text("RelayPulse").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            Spacer()
            Text("Eşitleme \(age(s.updated))").font(.system(size: 10)).foregroundStyle(dim)
        }
    }

    func count(_ n: Int, _ l: String, _ c: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(c).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: -1) {
                Text("\(n)").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                Text(l.uppercased()).font(.system(size: 8, weight: .medium)).foregroundStyle(dim).tracking(0.6)
            }
        }
    }

    func alarm(_ s: FleetSummary) -> some View {
        HStack(spacing: 5) {
            if let n = s.worstName {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(err)
                Text("\(n) · \(s.worstError ?? "") · \(age(s.worstSince))").foregroundStyle(err).lineLimit(1)
                if #available(iOSApplicationExtension 17.0, *) {
                    Spacer(minLength: 4)
                    fixButton(n)
                }
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(ok)
                Text("Alarm yok").foregroundStyle(dim)
            }
        }.font(.system(size: 10, weight: .medium))
    }

    /// Opens the app and runs the first auto-fix command on that relay.
    @available(iOSApplicationExtension 17.0, *)
    func fixButton(_ name: String) -> some View {
        Button(intent: FixRelayIntent(relay: name)) {
            Text("Onar")
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(err.opacity(0.22)))
                .foregroundStyle(err)
        }
        .buttonStyle(.plain)
    }

    func small(_ s: FleetSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(s)
            Spacer()
            HStack(spacing: 12) {
                Ring(s: s, size: 62)
                VStack(alignment: .leading, spacing: 5) {
                    count(s.online, "online", ok)
                    count(s.warn + s.stale, "sarı", warnC)
                    count(s.offline, "kırmızı", err)
                }
            }
            Spacer()
            alarm(s)
        }
    }

    func medium(_ s: FleetSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            header(s)
            HStack(alignment: .center, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(s.offline > 0 ? err : ok).frame(width: 12, height: 12)
                        .shadow(color: (s.offline > 0 ? err : ok).opacity(0.8), radius: 6)
                    VStack(alignment: .leading, spacing: -4) {
                        Text("\(s.online)").font(.system(size: 42, weight: .bold)).foregroundStyle(.white)
                        Text("AKTİF RELAY · \(s.total)").font(.system(size: 9, weight: .medium)).foregroundStyle(dim).tracking(0.8)
                    }
                }
                Spacer()
                Ring(s: s, size: 54)
                VStack(alignment: .leading, spacing: 4) {
                    count(s.online, "online", ok)
                    count(s.warn + s.stale, "sarı", warnC)
                    count(s.offline, "kırmızı", err)
                }
            }
            Sparkline(values: s.history).frame(height: 26)
            alarm(s)
        }
    }

    func inline(_ s: FleetSummary) -> some View {
        Text("\(s.online)/\(s.total) · \(s.warn + s.stale) ⚠ · \(s.offline) ✕")
    }

    func circular(_ s: FleetSummary) -> some View {
        let pct = s.total > 0 ? s.online * 100 / s.total : 0
        return ZStack {
            Circle().stroke(.secondary.opacity(0.3), lineWidth: 5)
            Circle().trim(from: 0, to: Double(pct) / 100).stroke(.primary, style: .init(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(pct)%").font(.system(size: 15, weight: .semibold))
        }
    }

    func rect(_ s: FleetSummary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(s.online)/\(s.total) çevrimiçi").font(.headline)
            if let n = s.worstName {
                Text(n).font(.caption)
                Text("\(s.worstError ?? "") · \(age(s.worstSince))").font(.caption2)
            } else {
                Text("Alarm yok").font(.caption)
            }
        }
    }
}

private let navy = LinearGradient(colors: [Color(red: 0.05, green: 0.09, blue: 0.20), Color(red: 0.09, green: 0.16, blue: 0.32)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)

extension View {
    @ViewBuilder func widgetBackground(dark: Bool) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(for: .widget) { if dark { navy } else { Color.clear } }
        } else {
            padding().background(dark ? AnyView(navy) : AnyView(Color.clear))
        }
    }
}

@main
struct RelayPulseWidgetBundle: WidgetBundle {
    var body: some Widget {
        RelayPulseWidget()
        OutageLiveActivity()
    }
}

struct RelayPulseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RelayPulseWidget", provider: Provider()) { e in
            WidgetFamilyHost(e: e)
        }
        .configurationDisplayName("Filo durumu")
        .description("Çevrimiçi / sarı / kırmızı relay sayısı, sağlık halkası ve son alarm.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

struct WidgetFamilyHost: View {
    @Environment(\.widgetFamily) var family
    let e: Entry
    var body: some View {
        let dark = family == .systemSmall || family == .systemMedium
        WidgetView(e: e).widgetBackground(dark: dark)
    }
}
