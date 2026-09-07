import SwiftUI

/// The paywall, opened from the dashboard notice or from Settings. It explains
/// what the purchase lifts and closes again -- it is not a gate: the app stays
/// usable on the free tier whether or not anyone buys.
struct UnlockView: View {
    @EnvironmentObject private var purchases: PurchaseStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false

    var body: some View {
        ZStack {
            Theme.bg(scheme).ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "lock.shield")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.accent(scheme))

                VStack(spacing: 8) {
                    Text("Unlock RelayPulse")
                        .font(.title.bold())
                        .foregroundStyle(Theme.text(scheme))
                    Text("RelayPulse watches up to \(FleetStore.freeRelayLimit) relays for free.\nUnlock it once to monitor your whole fleet.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted(scheme))
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    Button {
                        Task { busy = true; await purchases.purchase(); busy = false }
                    } label: {
                        Text(purchases.product.map { "Purchase RelayPulse Lifetime — \($0.displayPrice)" } ?? "Purchase RelayPulse Lifetime")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.accent(scheme))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(busy || purchases.product == nil)

                    Button("Restore Purchases") {
                        Task { busy = true; await purchases.restorePurchases(); busy = false }
                    }
                    .disabled(busy)

                    Button("Continue with \(FleetStore.freeRelayLimit) relays") { dismiss() }
                        .font(.footnote)

                    if let message = purchases.errorMessage {
                        Text(message).font(.caption).foregroundStyle(Theme.err(scheme))
                    }
                }
                .padding(.horizontal, 32)

                Spacer()
            }
        }
    }

}
