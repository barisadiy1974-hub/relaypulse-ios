import ActivityKit
import SwiftUI
import WidgetKit

private let err = Color(red: 0.95, green: 0.38, blue: 0.38)
private let dim = Color.white.opacity(0.55)

@available(iOSApplicationExtension 16.1, *)
struct OutageLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RelayOutageAttributes.self) { ctx in
            lockScreen(ctx.state)
                .activityBackgroundTint(Color(red: 0.05, green: 0.09, blue: 0.20))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("\(ctx.state.offlineCount)", systemImage: "exclamationmark.triangle.fill")
                        .font(.title3.weight(.semibold)).foregroundStyle(err)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(ctx.state.since, style: .timer)
                        .font(.title3.monospacedDigit()).foregroundStyle(err)
                        .multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(ctx.state.worstName).font(.headline).foregroundStyle(.white)
                    Text(ctx.state.offlineCount > 1
                         ? "\(ctx.state.offlineCount) relay çevrimdışı"
                         : "Relay çevrimdışı")
                        .font(.caption).foregroundStyle(dim)
                }
            } compactLeading: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(err)
            } compactTrailing: {
                Text(ctx.state.since, style: .timer)
                    .monospacedDigit().frame(maxWidth: 44).foregroundStyle(err)
            } minimal: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(err)
            }
            .keylineTint(err)
        }
    }

    private func lockScreen(_ st: RelayOutageAttributes.ContentState) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2).foregroundStyle(err)
            VStack(alignment: .leading, spacing: 2) {
                Text(st.worstName).font(.headline).foregroundStyle(.white)
                Text(st.offlineCount > 1 ? "\(st.offlineCount) relay çevrimdışı" : "Çevrimdışı")
                    .font(.caption).foregroundStyle(dim)
            }
            Spacer()
            Text(st.since, style: .timer)
                .font(.title2.monospacedDigit()).foregroundStyle(err)
                .frame(maxWidth: 82, alignment: .trailing)
        }
        .padding(.horizontal, 4)
    }
}
