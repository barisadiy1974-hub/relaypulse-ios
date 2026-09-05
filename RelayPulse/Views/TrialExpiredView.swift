import SwiftUI

/// Shown when the 14-day trial has expired and RelayPulse Lifetime has not been purchased.
struct TrialExpiredView: View {
    @EnvironmentObject private var purchases: PurchaseStore
    @Environment(\.colorScheme) private var scheme
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
                    Text("Trial Expired")
                        .font(.title.bold())
                        .foregroundStyle(Theme.text(scheme))
                    Text("Your 14-day free trial has ended.\nPurchase RelayPulse Lifetime to continue.")
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
