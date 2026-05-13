import Foundation

/// Calls the Vercel /api/scrub-instagram endpoint to distill an IG profile into
/// a style-profile description. Pro-gated on the UI side; this service is
/// just the network plumbing + per-device usage tracking.
final class ScrubService {

    static let shared = ScrubService()

    // MARK: - Configuration

    /// Production backend. Update if your Vercel project URL is different.
    private let baseURL: URL = {
        if let override = Bundle.main.object(forInfoDictionaryKey: "DumpsterAPIBaseURL") as? String,
           let u = URL(string: override) {
            return u
        }
        return URL(string: "https://dumpster-omega.vercel.app")!
    }()

    /// Free Pro users get this many scrubs per rolling 30 days.
    /// (Each scrub costs ~$0.05 Apify + a Claude call. Cap protects revenue.)
    static let monthlyScrubLimit = 10

    // MARK: - Response

    struct ScrubResult: Codable {
        let description: String
        let engagementPlaybook: String
        let postsAnalyzed: Int
        let hashtags: [String]
        let topPosts: [TopPost]

        struct TopPost: Codable {
            let firstLine: String
            let likes: Int
            let comments: Int
            let views: Int
            let productType: String
        }

        // Tolerate missing fields from older backend or fallback paths.
        enum CodingKeys: String, CodingKey {
            case description, engagementPlaybook, postsAnalyzed, hashtags, topPosts
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            description = (try? c.decode(String.self, forKey: .description)) ?? ""
            engagementPlaybook = (try? c.decode(String.self, forKey: .engagementPlaybook)) ?? ""
            postsAnalyzed = (try? c.decode(Int.self, forKey: .postsAnalyzed)) ?? 0
            hashtags = (try? c.decode([String].self, forKey: .hashtags)) ?? []
            topPosts = (try? c.decode([TopPost].self, forKey: .topPosts)) ?? []
        }
        init(description: String, engagementPlaybook: String, postsAnalyzed: Int, hashtags: [String], topPosts: [TopPost]) {
            self.description = description
            self.engagementPlaybook = engagementPlaybook
            self.postsAnalyzed = postsAnalyzed
            self.hashtags = hashtags
            self.topPosts = topPosts
        }
    }

    struct ScrubError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: - Public API

    /// Quota check + network call. Throws `ScrubError` on any failure.
    func scrub(profileURL: String, resultsLimit: Int = 12) async throws -> ScrubResult {
        try ensureUnderQuota()

        let url = baseURL.appendingPathComponent("api/scrub-instagram")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "profileURL": profileURL,
            "resultsLimit": resultsLimit
        ])

        let (data, response) = try await URLSession.shared.data(for: req)

        guard let http = response as? HTTPURLResponse else {
            throw ScrubError(message: "Network error.")
        }

        if http.statusCode != 200 {
            let detail = Self.extractError(from: data) ?? "Unknown error (HTTP \(http.statusCode))"
            throw ScrubError(message: detail)
        }

        let decoded = try JSONDecoder().decode(ScrubResult.self, from: data)
        recordSuccess()
        return decoded
    }

    // MARK: - Quota (per-device, persisted)

    private let storageKey = "scrub_history"

    /// Returns the timestamps of scrubs in the last 30 days.
    func recentScrubTimestamps() -> [Date] {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        let raw = UserDefaults.standard.array(forKey: storageKey) as? [Double] ?? []
        return raw.compactMap {
            let d = Date(timeIntervalSince1970: $0)
            return d >= cutoff ? d : nil
        }
    }

    /// 0…monthlyScrubLimit — how many have been used so far in the window.
    func usedThisMonth() -> Int { recentScrubTimestamps().count }

    /// True if the user still has scrubs available this rolling month.
    func canScrub() -> Bool { usedThisMonth() < Self.monthlyScrubLimit }

    private func ensureUnderQuota() throws {
        guard canScrub() else {
            throw ScrubError(message: "You've used all \(Self.monthlyScrubLimit) Instagram scrubs this month. Resets in a few days.")
        }
    }

    private func recordSuccess() {
        var arr = recentScrubTimestamps().map { $0.timeIntervalSince1970 }
        arr.append(Date().timeIntervalSince1970)
        UserDefaults.standard.set(arr, forKey: storageKey)
    }

    // MARK: - Helpers

    private static func extractError(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }
        if let err = obj["error"] as? String {
            if let detail = obj["detail"] as? String, !detail.isEmpty {
                return "\(err): \(detail)"
            }
            return err
        }
        return nil
    }
}
