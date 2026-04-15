import StoreKit
import Observation

// MARK: - StoreManager
//
// Manages the single Connectakt Pro non-consumable IAP via StoreKit 2.
// Inject into the SwiftUI environment via @State in ConnektaktApp.

@Observable
@MainActor
final class StoreManager {

    // MARK: - Product IDs

    static let proProductID = "com.ericerwin.connectakt.pro"

    // MARK: - State

    /// True when the user owns the Pro upgrade.
    private(set) var isPro: Bool = false

    /// The Pro product fetched from the App Store (nil until loaded).
    private(set) var proProduct: Product? = nil

    /// True while a purchase or restore is in progress.
    private(set) var isLoading: Bool = false

    /// Non-nil when a purchase/restore error should be shown.
    var errorMessage: String? = nil

    // MARK: - Init

    init() {
        Task { await load() }
        Task { await listenForTransactions() }
    }

    // MARK: - Public Actions

    func purchase() async {
        guard let product = proProduct else { return }
        isLoading = true
        errorMessage = nil
        do {
            let result = try await product.purchase()
            await handle(purchaseResult: result)
        } catch StoreKitError.userCancelled {
            // no-op
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func restore() async {
        isLoading = true
        errorMessage = nil
        do {
            try await AppStore.sync()
            await refreshEntitlement()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Private

    private func load() async {
        do {
            let products = try await Product.products(for: [Self.proProductID])
            proProduct = products.first
        } catch {
            // Not fatal — purchase button will remain disabled until retry
        }
        await refreshEntitlement()
    }

    private func refreshEntitlement() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result, tx.productID == Self.proProductID {
                isPro = true
                return
            }
        }
        // If no active entitlement found, leave isPro as-is (don't downgrade mid-session)
    }

    private func handle(purchaseResult: Product.PurchaseResult) async {
        switch purchaseResult {
        case .success(let verification):
            if case .verified(let tx) = verification {
                await tx.finish()
                isPro = true
            } else {
                errorMessage = "PURCHASE COULD NOT BE VERIFIED"
            }
        case .pending:
            break   // Ask-to-Buy or payment pending — handled via transaction listener
        case .userCancelled:
            break
        @unknown default:
            break
        }
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            if case .verified(let tx) = result, tx.productID == Self.proProductID {
                await tx.finish()
                isPro = true
            }
        }
    }
}
