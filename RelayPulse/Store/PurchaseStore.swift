import Foundation
import StoreKit

/// StoreKit 2 entitlement for the iOS app. There is no trial: the app is free
/// for a small fleet and the purchase lifts that limit, so nothing here can ever
/// lock someone out.
/// The matching non-consumable product must be created in App Store Connect.
@MainActor
final class PurchaseStore: ObservableObject {
    static let productID = "com.baris.relaypulse.pro.lifetime"

    @Published private(set) var product: Product?
    @Published private(set) var isEntitled = false
    @Published private(set) var errorMessage: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                await self.handle(result)
            }
        }
    }

    deinit { updatesTask?.cancel() }

    func start() async {
        await refreshEntitlement()
        do {
            product = try await Product.products(for: [Self.productID]).first
        } catch {
            errorMessage = "The purchase option is temporarily unavailable."
        }
    }

    func purchase() async {
        errorMessage = nil
        guard let product else {
            errorMessage = "The purchase option is not available yet."
            return
        }
        do {
            switch try await product.purchase() {
            case .success(let result):
                // handle() ignores anything StoreKit could not verify, so an
                // unverified receipt would otherwise leave the screen with no
                // unlock and no message — indistinguishable from a hang.
                guard case .verified = result else {
                    errorMessage = "The purchase could not be verified. If you were charged, tap Restore Purchase."
                    break
                }
                await handle(result)
            case .userCancelled:
                break
            case .pending:
                errorMessage = "Purchase is pending approval."
            @unknown default:
                errorMessage = "The purchase could not be completed."
            }
        } catch {
            errorMessage = "The purchase could not be completed."
        }
    }

    func restorePurchases() async {
        errorMessage = nil
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            if !isEntitled {
                errorMessage = "No previous RelayPulse Lifetime purchase was found."
            }
        } catch StoreKitError.userCancelled {
            // AppStore.sync() always asks the buyer to authenticate. Dismissing
            // that sheet is a decision, not a failure — and telling an owner
            // their purchases "could not be restored" reads like they lost them.
        } catch {
            errorMessage = "Purchases could not be restored."
        }
    }

    private func refreshEntitlement() async {
        #if DEBUG
        // Gelistirici derlemesi magaza makbuzu tasimaz; kendi telefonda tam filo icin.
        isEntitled = true
        return
        #endif
        var entitled = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                entitled = true
            }
        }
        isEntitled = entitled
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        if transaction.productID == Self.productID {
            isEntitled = transaction.revocationDate == nil
        }
        await transaction.finish()
    }
}
