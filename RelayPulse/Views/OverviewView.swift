import SwiftUI

/// Overview — mirrors the Mac app's "Overview" tab: the Anyone news/blog feed
/// plus the same shortcuts to X and Telegram that sit in the Mac's news toolbar.
struct OverviewView: View {
    private static let blog = URL(string: "https://www.anyone.io/blog")!
    private static let x = URL(string: "https://x.com/anyoneprotocol")!
    private static let telegram = URL(string: "https://t.me/anyoneprotocol")!

    @Environment(\.openURL) private var openURL

    var body: some View {
        WebDashboardView(title: "Overview", url: Self.blog)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { openURL(Self.x) } label: {
                        Label("Open X", systemImage: "at")
                    }
                    Button { openURL(Self.telegram) } label: {
                        Label("Open Telegram", systemImage: "paperplane")
                    }
                }
            }
    }
}
