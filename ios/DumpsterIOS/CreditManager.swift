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

    // MARK: - Server verification

    /// Production backend. Update if your Vercel project URL is different.
    private let baseURL: URL = {
        if let override = Bundle.main.object(forInfoDictionaryKey: "DumpsterAPIBaseURL") as? String,
           let u = URL(string: override) {
            return u
        }
        return URL(string: "https://dumpster-web-manus.vercel.app")!
    }()

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
                    // On-device StoreKit verification only proves Apple *signed* a
                    // transaction — it doesn't tell our server anything happened. Report
                    // it server-side so Supabase's credit ledger (the one AI-call gating
                    // actually reads from on web) reflects the purchase too, and so a
                    // forged/replayed transaction can't be waved through by a client that
                    // skips this call — the server independently re-verifies the JWS.
                    // (The signed JWS lives on the VerificationResult, not the unwrapped
                    // Transaction — that's what re-verifying the signature needs.)
                    await reportPurchaseToServer(jws: verification.jwsRepresentation)
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

    /// Best-effort: tells our server about a verified StoreKit transaction so it's
    /// recorded (and re-verified independently) in Supabase. Never blocks or fails the
    /// purchase — the user already paid Apple, so a network hiccup here shouldn't cost
    /// them credits they're owed. Failures are logged, not surfaced to the UI.
    private func reportPurchaseToServer(jws: String) async {
        guard let jwt = AuthManager.shared.jwt else { return }

        var req = URLRequest(url: baseURL.appendingPathComponent("api/iap-verify"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                "signedTransaction": jws
            ])
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                CrashReporter.shared.capture(
                    NSError(domain: "CreditManager", code: http.statusCode),
                    tags: ["op": "iap_verify", "status": String(http.statusCode)]
                )
            }
        } catch {
            CrashReporter.shared.capture(error, tags: ["op": "iap_verify"])
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
        } catch {
            purchaseError = "Restore failed: \(error.localizedDescription)"
        }
    }
}
