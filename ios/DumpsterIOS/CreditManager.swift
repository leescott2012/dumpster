import Foundation
import StoreKit
import UIKit
import Combine

// MARK: - Credit Manager

/// Manages the user's AI credit balance and in-app purchases.
/// The balance is read from the server (profiles) and kept live from the
/// X-Credits-Remaining response header; the device never writes it.
@MainActor
final class CreditManager: ObservableObject {

    // MARK: - Singleton
    static let shared = CreditManager()

    // MARK: - Published State
    @Published private(set) var balance: Int = 0
    @Published private(set) var products: [Product] = []
    /// Set when any server AI call returns 402; the app root shows the credits sheet.
    @Published var showOutOfCredits = false
    @Published var isPurchasing = false
    @Published var purchaseError: String?
    @Published var lastPurchaseSuccess: CreditPack?

    /// True once a balance has been read from the server this session.
    @Published private(set) var hasLoaded = false

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

    // MARK: - Credit Costs (server is the source of truth — server/creditGate.ts COSTS)
    // Only calls that hit the Dumpster server spend credits. On native that is
    // Scan (/api/ai-label) and IG Scrub. Suggest runs on-device; Captions and
    // the Valet use the user's own provider key — neither is charged.
    enum Cost {
        static let scanRequest = 12   // per /api/ai-label request (server cap 12 photos each)
        static let igScrub = 5
        static let scanBatchPhotos = 12
        static func scan(photoCount: Int) -> Int {
            photoCount <= 0 ? 0 : ((photoCount + scanBatchPhotos - 1) / scanBatchPhotos) * scanRequest
        }
    }

    // MARK: - Init
    private init() {
        Task { await fetchProducts() }
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // Sign-in / sign-out / token refresh → re-read.
        authSub = AuthManager.shared.$session.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }
    private var authSub: AnyCancellable?

    // MARK: - Server verification

    /// Production backend. Update if your Vercel project URL is different.
    private let baseURL: URL = {
        if let override = Bundle.main.object(forInfoDictionaryKey: "DumpsterAPIBaseURL") as? String,
           let u = URL(string: override) {
            return u
        }
        return URL(string: "https://dumpster-web-manus.vercel.app")!
    }()

    // MARK: - Balance (read-only on the device)
    // The profiles table only lets the client write onboarding/avatar fields, so
    // credits are NEVER written from here — we only read them.

    func canAfford(_ cost: Int) -> Bool { balance >= cost }

    /// Re-read the balance from the server.
    func refresh() {
        Task { await fetchBalance() }
    }

    /// Re-read now and again after ~2.5s (refunds land after the response is sent).
    func refreshSoonAndLater() {
        refresh()
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await fetchBalance()
        }
    }

    /// Call after every credit-charged response (Scan, IG Scrub). On 2xx the server's
    /// X-Credits-Remaining is the post-deduct balance; on anything else (402, 5xx,
    /// network failure → nil) re-read, because a refund may still be landing.
    func noteAIResponse(_ http: HTTPURLResponse?) {
        // 402 = server says out of credits: show the top-up sheet (DumpsterApp presents it).
        if http?.statusCode == 402 { showOutOfCredits = true }
        if let http, (200..<300).contains(http.statusCode),
           let h = http.value(forHTTPHeaderField: "X-Credits-Remaining"), let n = Int(h) {
            balance = max(0, n)
            hasLoaded = true
        } else {
            refreshSoonAndLater()
        }
    }

    private func fetchBalance() async {
        guard let uid = AuthManager.shared.userId, let jwt = AuthManager.shared.jwt else {
            balance = 0
            hasLoaded = false
            return
        }
        do {
            let data = try await SupabaseClient.shared.get(
                table: "profiles",
                query: "id=eq.\(uid)&select=credits,daily_credits_remaining,daily_credits_reset_at,subscription_tier",
                jwt: jwt)
            guard let row = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]])?.first else { return }
            let purchased = (row["credits"] as? NSNumber)?.intValue ?? 0
            var daily = (row["daily_credits_remaining"] as? NSNumber)?.intValue ?? 0
            // Display only — the server performs the real 24h reset on the next spend.
            if let s = row["daily_credits_reset_at"] as? String, let d = Self.parseISO(s),
               Date().timeIntervalSince(d) > 24 * 3600 {
                daily = (row["subscription_tier"] as? String) == "pro" ? 200 : 15
            }
            balance = purchased + daily
            hasLoaded = true
        } catch {
            // Keep the last known balance on a transient failure.
        }
    }

    private static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
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
            // Never grant credits locally — the server ledger is the only source.
            purchaseError = "The store isn't available right now. Try again in a moment."
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
                    refreshSoonAndLater()   // server credited the pack; show it
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
