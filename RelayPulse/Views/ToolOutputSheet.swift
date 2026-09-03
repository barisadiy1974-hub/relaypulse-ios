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
            ScrollView([.horizontal, .vertical]) {
                Text(output.text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(output.failed ? Theme.err(scheme) : Theme.text(scheme))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
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
