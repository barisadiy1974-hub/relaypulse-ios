import SwiftUI

/// iOS 15 support shims.
///
/// The app targets iOS 15 so an iPhone 7 (stuck on 15.8) can run it, but newer
/// phones should not lose the newer SwiftUI behaviour. Each shim therefore keeps
/// the modern API where it exists and only falls back below it — the availability
/// check lives here once instead of being repeated at every call site.

/// `NavigationStack` on iOS 16+, `NavigationView` below it.
struct NavStack<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack { content() }
        } else {
            NavigationView { content() }
                // Without this iPhones in landscape get the split-view behaviour
                // and the list can render as an empty sidebar.
                .navigationViewStyle(.stack)
        }
    }
}

/// `LabeledContent` equivalent: label on the left, value on the right.
/// Both call shapes are supported — a plain string value, or arbitrary content.
struct LabeledRow<Content: View>: View {
    private let label: String
    private let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            LabeledContent(label) { content }
        } else {
            HStack {
                Text(label)
                Spacer(minLength: 12)
                content.multilineTextAlignment(.trailing)
            }
        }
    }
}

extension LabeledRow where Content == Text {
    /// `Text.foregroundColor` (unlike `foregroundStyle`) returns `Text`, which is
    /// what keeps this specialisation concrete instead of needing AnyView.
    init(_ label: String, value: String) {
        self.init(label) { Text(value).foregroundColor(.secondary) }
    }
}

/// `ContentUnavailableView` equivalent for empty lists.
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView(title, systemImage: systemImage,
                                   description: Text(message))
        } else {
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text(title).font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)
        }
    }
}

/// `ShareLink` equivalent — below iOS 16 it presents a UIActivityViewController.
struct ShareTextButton: View {
    let text: String
    @State private var sharing = false

    var body: some View {
        if #available(iOS 16.0, *) {
            ShareLink(item: text) { Image(systemName: "square.and.arrow.up") }
        } else {
            Button { sharing = true } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .sheet(isPresented: $sharing) { ActivitySheet(items: [text]) }
        }
    }
}

private struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

extension View {
    /// `.scrollContentBackground(.hidden)` on iOS 16+, no-op below (iOS 15 lists
    /// already draw on the grouped background, so the plain view is acceptable).
    @ViewBuilder
    func hideScrollBackground() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}
