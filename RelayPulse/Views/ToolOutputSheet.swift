import SwiftUI

/// Output of one tool or command.
struct ToolOutput: Identifiable {
    let id = UUID()
    let title: String
    let text: String
    let failed: Bool
}

/// Shows the output full screen, selectable and shareable.
struct ToolOutputSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    let output: ToolOutput

    var body: some View {
        NavStack {
            // Vertical scroll wrapping a horizontal one, rather than a single
            // two-axis ScrollView: a two-axis scroll view centres content that
            // is smaller than its viewport, which left short output — an error
            // line especially — floating in the middle of an empty sheet and
            // running off the right edge. Nesting pins it to the top-left while
            // still letting wide terminal output scroll sideways.
            ScrollView(.vertical) {
                ScrollView(.horizontal) {
                    Text(output.text)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(output.failed ? Theme.err(scheme) : Theme.text(scheme))
                        .textSelection(.enabled)
                        .padding(12)
                }
            }
            .background(Theme.bg(scheme))
            .navigationTitle(output.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .navigationBarLeading) {
                    ShareTextButton(text: output.text)
                }
            }
        }
    }
}
