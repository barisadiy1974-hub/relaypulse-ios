import Foundation
import StoreKit

/// StoreKit 2 entitlement for the iOS app. A seven-day full-fleet preview
/// falls back to the permanent free three-relay tier; purchase lifts the limit.
/// The matching non-consumable product must be created in App Store Connect.
@MainActor
final class PurchaseStore: ObservableObject {
    static let productID = "com.baris.relaypulse.pro.lifetime"
    private static let previewStartKey = "fullFleetPreviewStartedAt"
    // ponytail: device-local timing is not cross-device fraud prevention; add account-backed entitlement only if that becomes necessary.
    private static let previewDuration: TimeInterval = 7 * 24 * 60 * 60

    /// Son dogrulanan hak, acilista hemen bilinsin diye onbellekte tutulur.
    /// Onbelleksiz her soguk acilista StoreKit cevap verene kadar izlenen filo
    /// ucretsiz dilime (3 relay) dusuyordu.
    static let entitledKey = "entitledCache"

    @Published private(set) var product: Product?
    @Published private(set) var isEntitled = UserDefaults.standard.bool(forKey: PurchaseStore.entitledKey) {
        didSet {
            // Sadece Release yazar. Debug derlemesi asagida hakki kosulsuz true
            // yapiyor; onu diske yazarsa uzerine kurulan TestFlight/App Store
            // derlemesi de acilista tam filo ile basliyor (demo kapatilinca
            // 3-relay limitine dusmez). Cache yalnizca gercek makbuzu yansitmali.
            #if !DEBUG
            UserDefaults.standard.set(isEntitled, forKey: Self.entitledKey)
            #endif
        }
    }
    @Published private(set) var trialEndsAt: Date?
    @Published private(set) var errorMessage: String?
    /// Positive result of a restore. Without it a restore on an account that
    /// already owns Lifetime changed nothing on screen, and the operator took
    /// the silence for a failure and restored again (2026-09-24).
    @Published private(set) var infoMessage: String?

    private var updatesTask: Task<Void, Never>?
    private var trialExpiryTask: Task<Void, Never>?

    var hasFullFleetAccess: Bool { isEntitled || trialEndsAt != nil }
    var isTrialActive: Bool { !isEntitled && trialEndsAt != nil }

    init() {
        refreshTrialWindow()
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                await self.handle(result)
            }
        }
    }

    deinit {
        updatesTask?.cancel()
        trialExpiryTask?.cancel()
    }

    func start() async {
        await refreshEntitlement()
        refreshTrialWindow()
        do {
            product = try await Product.products(for: [Self.productID]).first
            // Bos liste HATA FIRLATMIYOR: urun gelmeyince product sessizce nil kaliyor
            // ve eskiden satin alma satiri tamamen kayboluyordu. Sebebini ekranda soyle.
            errorMessage = product == nil
                ? "The purchase is temporarily unavailable. Check your connection and tap Retry."
                : nil
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
        infoMessage = nil
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            if isEntitled {
                infoMessage = "RelayPulse Lifetime is active on this Apple Account."
            } else {
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
        #else
        var entitled = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                entitled = true
            }
        }
        isEntitled = entitled
        #endif
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        if transaction.productID == Self.productID {
            isEntitled = transaction.revocationDate == nil
            refreshTrialWindow()
        }
        await transaction.finish()
    }

    private func refreshTrialWindow() {
        trialExpiryTask?.cancel()
        guard !isEntitled else {
            trialEndsAt = nil
            return
        }

        let now = Date()
        let startedAt: Date
        if let timestamp = TimeInterval(Keychain.get(Self.previewStartKey)) {
            startedAt = Date(timeIntervalSince1970: timestamp)
        } else {
            startedAt = now
            Keychain.set(String(startedAt.timeIntervalSince1970), for: Self.previewStartKey)
        }

        let endsAt = startedAt.addingTimeInterval(Self.previewDuration)
        guard endsAt > now else {
            trialEndsAt = nil
            return
        }

        trialEndsAt = endsAt
        let wait = UInt64((endsAt.timeIntervalSince(now) * 1_000_000_000).rounded(.up))
        trialExpiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: wait)
            guard !Task.isCancelled else { return }
            self?.trialEndsAt = nil
        }
    }
}
