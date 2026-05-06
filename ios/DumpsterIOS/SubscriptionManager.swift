import Foundation
import StoreKit

// MARK: - Subscription Manager

/// Manages DUMPSTER Pro auto-renewing subscription.
/// While `isPro == true` the user gets unlimited AI actions and credit gates are bypassed.
@MainActor
final class SubscriptionManager: ObservableObject {

    // MARK: - Singleton
    static let shared = SubscriptionManager()

    // MARK: - Published State
    @Published private(set) var isPro: Bool = false
    @Published private(set) var products: [Product] = []
    @Published private(set) var activeProductID: String?
    @Published var isPurchasing = false
    @Published var purchaseError: String?

    // MARK: - Plans
    struct Plan: Identifiable, Equatable {
        let id: String              // StoreKit product ID
        let title: String           // "Monthly", "Yearly"
        let displayPrice: String    // Fallback if StoreKit not loaded
        let perPeriod: String       // "/month", "/year"
        let badge: String?
        let savings: String?

        static let all: [Plan] = [
            Plan(
                id: "com.dumpster.pro.weekly",
                title: "Weekly",
                displayPrice: "$2.99",
                perPeriod: "/week",
                badge: nil,
                savings: nil
            ),
            Plan(
                id: "com.dumpster.pro.monthly",
                title: "Monthly",
                displayPrice: "$4.99",
                perPeriod: "/month",
                badge: nil,
                savings: nil
            ),
            Plan(
                id: "com.dumpster.pro.yearly",
                title: "Yearly",
                displayPrice: "$29.99",
                perPeriod: "/year",
                badge: "BEST VALUE",
                savings: "Save 47%"
            ),
        ]
    }

    // MARK: - Init
    private var updateListenerTask: Task<Void, Never>?

    private init() {
        updateListenerTask = listenForTransactions()
        Task {
            await fetchProducts()
            await refreshEntitlement()
        }
    }

    deinit { updateListenerTask?.cancel() }

    // MARK: - Products

    func fetchProducts() async {
        let ids = Plan.all.map { $0.id }
        do {
            let fetched = try await Product.products(for: ids)
            // Sort by price ascending
            products = fetched.sorted { $0.price < $1.price }
        } catch {
            print("[SubscriptionManager] Failed to fetch products: \(error)")
        }
    }

    // MARK: - Entitlement

    /// Walks current entitlements and updates `isPro`.
    func refreshEntitlement() async {
        var active = false
        var activeID: String?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result else { continue }
            if Plan.all.contains(where: { $0.id == tx.productID }),
               tx.revocationDate == nil,
               !(tx.isUpgraded) {
                active = true
                activeID = tx.productID
            }
        }
        isPro = active
        activeProductID = activeID
    }

    /// Listens for renewals/refunds while the app is running.
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let tx) = result {
                    await tx.finish()
                    await self.refreshEntitlement()
                }
            }
        }
    }

    // MARK: - Purchase

    func purchase(_ plan: Plan) async {
        guard let product = products.first(where: { $0.id == plan.id }) else {
            purchaseError = "Plan not available right now. Try again in a moment."
            return
        }
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let tx):
                    await tx.finish()
                    await refreshEntitlement()
                case .unverified:
                    purchaseError = "Purchase could not be verified. Please contact support."
                }
            case .pending:
                purchaseError = "Purchase is pending approval."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = "Purchase failed: \(error.localizedDescription)"
            CrashReporter.shared.capture(error, tags: ["op": "subscription_purchase", "plan": plan.id])
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlement()
        } catch {
            purchaseError = "Restore failed: \(error.localizedDescription)"
            CrashReporter.shared.capture(error, tags: ["op": "subscription_restore"])
        }
    }

    // MARK: - Display Helpers

    /// Returns the localized price string for a plan, falling back to hardcoded.
    func price(for plan: Plan) -> String {
        products.first(where: { $0.id == plan.id })?.displayPrice ?? plan.displayPrice
    }
}
