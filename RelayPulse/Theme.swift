import SwiftUI

/// Color palette — matches Mac RelayPulse renderer/styles.css.
/// Light = :root, Dark = [data-theme="dark"].
enum Theme {
    static func bg(_ s: ColorScheme) -> Color        { s == .dark ? hex(0x080A0F) : hex(0xF4F7FB) }
    static func panel(_ s: ColorScheme) -> Color      { s == .dark ? hex(0x0F1420) : hex(0xFFFFFF) }
    static func panel2(_ s: ColorScheme) -> Color     { s == .dark ? hex(0x141B2A) : hex(0xF7F9FC) }
    static func panel3(_ s: ColorScheme) -> Color     { s == .dark ? hex(0x1A2236) : hex(0xEEF3F9) }
    static func border(_ s: ColorScheme) -> Color     { s == .dark ? hex(0x1E2840) : hex(0xDBE4F0) }
    static func borderBright(_ s: ColorScheme) -> Color { s == .dark ? hex(0x2A3650) : hex(0xC5D3E5) }
    static func text(_ s: ColorScheme) -> Color       { s == .dark ? hex(0xE8ECF4) : hex(0x172033) }
    static func muted(_ s: ColorScheme) -> Color      { s == .dark ? hex(0x6B7A96) : hex(0x6A7890) }
    static func accent(_ s: ColorScheme) -> Color     { s == .dark ? hex(0x7DD3FC) : hex(0x2F7DF6) }
    static func ok(_ s: ColorScheme) -> Color         { s == .dark ? hex(0x34D399) : hex(0x2EA44F) }
    static func warn(_ s: ColorScheme) -> Color       { s == .dark ? hex(0xFBBF24) : hex(0xF5A623) }
    static func err(_ s: ColorScheme) -> Color        { s == .dark ? hex(0xF87171) : hex(0xE45858) }
    static func rx(_ s: ColorScheme) -> Color         { s == .dark ? hex(0x60A5FA) : hex(0x2F7DF6) }
    static func tx(_ s: ColorScheme) -> Color         { s == .dark ? hex(0x4ADE80) : hex(0x31B157) }

    static func hex(_ v: UInt32) -> Color {
        Color(.sRGB,
              red: Double((v >> 16) & 0xFF) / 255,
              green: Double((v >> 8) & 0xFF) / 255,
              blue: Double(v & 0xFF) / 255,
              opacity: 1)
    }
}

/// Card / panel view — matches Mac .card (gradient, 14px radius, thin border).
struct PanelCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    var stateColor: Color?
    var dimmed: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
            .background(
                LinearGradient(colors: [Theme.panel(scheme), Theme.panel2(scheme)],
                               startPoint: .top, endPoint: .bottom)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(stateColor?.opacity(0.32) ?? Theme.border(scheme), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .opacity(dimmed ? 0.72 : 1)
            .shadow(color: Color.black.opacity(scheme == .dark ? 0.35 : 0.08), radius: 10, x: 0, y: 6)
    }
}

/// Mac .relay-chip — state-colored pill badge.
struct StatePill: View {
    @Environment(\.colorScheme) private var scheme
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .tracking(0.3)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.12))
            .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 1))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
