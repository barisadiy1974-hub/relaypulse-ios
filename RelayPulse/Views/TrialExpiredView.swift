import SwiftUI

/// Shown when the 14-day trial has expired and no license key is active.
struct TrialExpiredView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var keyInput = ""
    @State private var error = ""
    @State private var activated = false

    var body: some View {
        ZStack {
            Theme.bg(scheme).ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "lock.shield")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.accent(scheme))

                VStack(spacing: 8) {
                    Text("Trial Expired")
                        .font(.title.bold())
                        .foregroundStyle(Theme.text(scheme))
                    Text("Your 14-day free trial has ended.\nEnter a license key to continue.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted(scheme))
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    TextField("RP1-XXXXXXXX-…", text: $keyInput)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .padding(12)
                        .background(Theme.panel(scheme))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border(scheme)))

                    if !error.isEmpty {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Theme.err(scheme))
                    }

                    Button(action: activate) {
                        Text("Activate")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.accent(scheme))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 32)

                Spacer()
            }
        }
    }

    private func activate() {
        let k = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if LicenseStore.activate(k) {
            activated = true
        } else {
            error = "Invalid license key. Check the key and try again."
        }
    }
}
