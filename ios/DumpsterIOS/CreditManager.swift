import Foundation
import StoreKit

// MARK: - Credit Manager

/// Manages the user's AI credit balance and in-app purchases.
/// Credits are persisted in UserDefaults and gated before every AI call.
@MainActor
final class CreditManager: ObservableObject {

    // MARK: - Singleton
    static let shared = CreditManager()

    // MARK: - Published State
    @Published private(set) var balance: Int = 0
    @Published private(set) var products: [Product] = []
    @Published var isPurchasing = false
    @Published var purchaseError: String?
    @Published var lastPurchaseSuccess: CreditPack?

    // MARK: - Constants
    private let balanceKey = "dumpster_credit_balance"
    private let hasOnboardedKey = "dumpster_credits_onboarded"
    static let freeStarterCredits = 10

    // MARK: - Credit Packs
    struct CreditPack: Identifiable, Equatable {
        let id: String          // StoreKit product ID
        let credits: Int
        let displayPrice: String
        let badge: String?

        static let all: [CreditPack] = [
            CreditPack(id: "com.dumpster.credits.50",  credits: 50,  displayPrice: "$1.99", badge: nil),
            CreditPack(id: "com.dumpster.credits.200", credits: 200, displayPrice: "$4.99", badge: "⭐ Popular"),
            CreditPack(id: "com.dumpster.credits.500", credits: 500, displayPrice: "$9.99", badge: nil),
        ]
    }

    // MARK: - Credit Costs
    enum AIAction: String {
        case generateCaptions  = "Generate Captions"
        case checkVibe         = "Check Vibe"
        case analyzePhotos     = "Analyze Photos"

        var cost: Int { 1 }
    }

    // MARK: - Init
    private init() {
        loadBalance()
        Task { await fetchProducts() }
    }

    // MARK: - Balance Management

    private func loadBalance() {
        if !UserDefaults.standard.bool(forKey: hasOnboardedKey) {
            // First launch — give free starter credits
            balance = Self.freeStarterCredits
            UserDefaults.standard.set(balance, forKey: balanceKey)
            UserDefaults.standard.set(true, forKey: hasOnboardedKey)
        } else {
            balance = UserDefaults.standard.integer(forKey: balanceKey)
        }
    }

    private func saveBalance() {
        UserDefaults.standard.set(balance, forKey: balanceKey)
    }

    /// Returns true if the user has enough credits for the action.
    func canAfford(_ action: AIAction) -> Bool {
        balance >= action.cost
    }

    /// Deducts credits for an AI action. Call AFTER a successful AI response.
    /// Returns false if insufficient credits (shouldn't happen if you gate with canAfford first).
    @discardableResult
    func spend(_ action: AIAction) -> Bool {
        guard balance >= action.cost else { return false }
        balance -= action.cost
        saveBalance()
        return true
    }

    /// Add credits (called after successful purchase).
    func addCredits(_ amount: Int) {
        balance += amount
        saveBalance()
    }

    // MARK: - StoreKit 2

    func fetchProducts() async {
        let ids = CreditPack.all.map { $0.id }
        do {
            let fetched = try await Product.products(for: ids)
            // Sort by price ascending
            products = fetched.sorted { $0.price < $1.price }
        } catch {
            CrashReporter.shared.capture(error, tags: ["op": "credits_fetch_products"])
        }
    }

    func purchase(_ pack: CreditPack) async {
        guard let product = products.first(where: { $0.id == pack.id }) else {
            // No StoreKit product yet (e.g. sandbox not configured) — use fallback
            addCredits(pack.credits)
            lastPurchaseSuccess = pack
            return
        }

        isPurchasing = true
        purchaseError = nil

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    addCredits(pack.credits)
                    lastPurchaseSuccess = pack
                    await transaction.finish()
                case .unverified:
                    purchaseError = "Purchase could not be verified. Please contact support."
                }
            case .pending:
                purchaseError = "Purchase is pending approval."
            case .userCancelled:
                break // No error shown on cancel
            @unknown default:
                break
            }
        } catch {
            purchaseError = "Purchase failed: \(error.localizedDescription)"
        }

        isPurchasing = false
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
        } catch {
            purchaseError = "Restore failed: \(error.localizedDescription)"
        }
    }
}
