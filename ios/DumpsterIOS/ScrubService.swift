import Foundation
import UIKit
import ImageIO

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
        return URL(string: "https://dumpster-web-manus.vercel.app")!
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
        let decoded = try await fetchScrub(profileURL: profileURL, resultsLimit: resultsLimit)
        recordSuccess()
        return decoded
    }

    // MARK: - Onboarding entry point (free)

    struct LinkResult {
        let ok: Bool
        let handle: String
        /// Plain-English reason when ok == false. Show as-is.
        let error: String?
        /// false if profiles.instagram_handle column isn't live yet; taste profile still saved.
        let linked: Bool
    }

    /// "@name" / "name" / instagram.com/name/... -> "name", nil if not a profile handle.
    static func parseHandle(_ input: String) -> String? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let pats = ["instagram\\.com/([A-Za-z0-9._]+)", "^@?([A-Za-z0-9._]{1,30})$"]
        for p in pats {
            if let r = try? NSRegularExpression(pattern: p, options: .caseInsensitive),
               let m = r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
               let range = Range(m.range(at: 1), in: s) {
                let h = String(s[range])
                let reserved = ["p", "reel", "reels", "tv", "stories", "explore", "accounts", "direct", "about", "s"]
                return reserved.contains(h.lowercased()) ? nil : h
            }
        }
        return nil
    }

    /// SINGLE ENTRY POINT for onboarding: call right after the handle is entered.
    /// Validates -> FREE scrub (no credits, no per-device monthly cap) -> saves style +
    /// playbook (Valet reads both via LLMService.userContextBlock; cloud-synced) ->
    /// links the handle on profiles.instagram_handle. Never throws.
    func linkInstagramAndBuildTaste(handle input: String) async -> LinkResult {
        guard let handle = Self.parseHandle(input) else {
            return LinkResult(ok: false, handle: "", error: "That doesn't look like an Instagram handle. Enter it like @yourname.", linked: false)
        }
        do {
            let r = try await fetchScrub(profileURL: handle, resultsLimit: 12)
            let d = UserDefaults.standard
            func merge(_ old: String, _ new: String) -> String {
                let o = old.trimmingCharacters(in: .whitespacesAndNewlines)
                return String((o.isEmpty ? new : o + "\n\n" + new).prefix(750))
            }
            d.set(merge(d.string(forKey: "ai_style_profile") ?? "", r.description), forKey: "ai_style_profile")
            if !r.engagementPlaybook.isEmpty {
                d.set(merge(d.string(forKey: "ai_engagement_playbook") ?? "", r.engagementPlaybook), forKey: "ai_engagement_playbook")
            }
            d.set(handle, forKey: "ig_handle")
            var linked = false
            if let uid = await AuthManager.shared.userId, let jwt = await AuthManager.shared.jwt {
                await AIProfileSync.shared.scheduleSave(userId: uid, jwt: jwt)
                linked = await patchHandle(handle, userId: uid, jwt: jwt)
            }
            return LinkResult(ok: true, handle: handle, error: nil, linked: linked)
        } catch {
            return LinkResult(ok: false, handle: handle, error: error.localizedDescription, linked: false)
        }
    }

    private func patchHandle(_ handle: String, userId: String, jwt: String) async -> Bool {
        guard let url = URL(string: "\(SupabaseClient.url)/rest/v1/profiles?id=eq.\(userId)") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        SupabaseClient.shared.authHeaders(jwt: jwt).forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["instagram_handle": handle])
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }

    private func fetchScrub(profileURL: String, resultsLimit: Int) async throws -> ScrubResult {

        // The production endpoint sits behind the credit gate — needs a signed-in session.
        guard let jwt = await AuthManager.shared.jwt else {
            throw ScrubError(message: "Sign in to your Dumpster account to use Instagram scrub.")
        }

        let url = baseURL.appendingPathComponent("api/scrub-instagram")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "profileURL": profileURL,
            "resultsLimit": resultsLimit
        ])

        req.timeoutInterval = 70 // server budget is ~55s
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            await CreditManager.shared.noteAIResponse(nil)   // may have been charged; re-read
            throw ScrubError(message: "Can't reach Dumpster right now. Check your connection and try again.")
        }

        guard let http = response as? HTTPURLResponse else {
            await CreditManager.shared.noteAIResponse(nil)
            throw ScrubError(message: "Network error.")
        }
        // 2xx: balance from X-Credits-Remaining. Anything else (402 insufficient, or a
        // failure the server refunds after responding): re-read now and in ~2.5s.
        await CreditManager.shared.noteAIResponse(http)

        if http.statusCode == 402 {
            throw ScrubError(message: "Not enough credits for an Instagram scrub (\(CreditManager.Cost.igScrub) credits). Get more credits and try again.")
        }
        if http.statusCode != 200 {
            throw ScrubError(message: Self.extractError(from: data) ?? Self.fallbackMessage(http.statusCode))
        }

        guard let decoded = try? JSONDecoder().decode(ScrubResult.self, from: data) else {
            throw ScrubError(message: "Got an unreadable answer from the server. Try again.")
        }
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

    private static func fallbackMessage(_ status: Int) -> String {
        switch status {
        case 401: return "Sign in to your Dumpster account, then try again."
        case 429: return "Too many tries. Wait a few minutes and try again."
        case 502, 504: return "Instagram took too long to answer. Try again in a minute."
        default: return "Couldn't read that profile (error \(status)). Try again in a minute."
        }
    }

    /// Server errors are plain English already; show as-is. HTML/gateway bodies are ignored.
    private static func extractError(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let err = obj["error"] as? String, !err.isEmpty else { return nil }
        return err
    }
}

// MARK: - LabelService

/// Calls /api/ai-label (Claude Vision, credit-gated) for specific photo labels —
/// same classifier and prompt the web Scan uses. Callers fall back to on-device
/// Apple Vision (PhotoAnalyzer) when this throws: signed out, offline, or out
/// of credits. Lives in this file to avoid a project.pbxproj registration.
final class LabelService {

    static let shared = LabelService()

    private let baseURL: URL = {
        if let override = Bundle.main.object(forInfoDictionaryKey: "DumpsterAPIBaseURL") as? String,
           let u = URL(string: override) {
            return u
        }
        return URL(string: "https://dumpster-web-manus.vercel.app")!
    }()

    /// Server chunk limit — /api/ai-label caps at 12 photos per request.
    private static let batchSize = 12

    struct LabelResult: Codable {
        let id: String
        let category: String
        let label: String
        let confidence: Double?
    }
    private struct LabelResponse: Codable { let labels: [LabelResult] }

    struct LabelError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    enum Outcome {
        case ok([LabelResult])
        /// 402 / 429 / 503 — out of credits, burst/daily cap, or budget. `daily` = long back-off.
        case quota(daily: Bool)
        case failed
    }

    /// One /api/ai-label request. `auto` = the free, server-capped auto-label path
    /// (no credits); `audit` = independent second look. Only { id, url } is sent —
    /// no EXIF/GPS. Callers must never pass video files.
    func request(photos: [(id: String, relativePath: String)], jwt: String, auto: Bool, audit: Bool) async -> Outcome {
        var batch: [[String: String]] = []
        for photo in photos {
            guard let dataUrl = Self.jpegDataURL(relativePath: photo.relativePath) else { continue }
            batch.append(["id": photo.id, "url": dataUrl])
        }
        guard !batch.isEmpty else { return .ok([]) }
        var req = URLRequest(url: baseURL.appendingPathComponent("api/ai-label"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = ["photos": batch]
        if auto { body["auto"] = true }
        if audit { body["audit"] = true }
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { return .failed }
            if !auto { await CreditManager.shared.noteAIResponse(http) }   // paid path only
            if [402, 429, 503].contains(http.statusCode) {
                let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["code"] as? String
                return .quota(daily: code != "rate_limit_exceeded")
            }
            guard http.statusCode == 200 else { return .failed }
            return .ok(try JSONDecoder().decode(LabelResponse.self, from: data).labels)
        } catch {
            if !auto { await CreditManager.shared.noteAIResponse(nil) }
            return .failed
        }
    }

    /// Paid Scan: label photos by Documents-relative path in batches. Per-batch
    /// failures (network blip, 402, one bad image) are swallowed rather than thrown —
    /// a failure in batch 2 of 3 must not discard batch 1's already-succeeded
    /// results and force every photo back to the Vision fallback. Missing ids in the
    /// returned array are the caller's signal to fall back for just those.
    func label(photos: [(id: String, relativePath: String)], jwt: String) async -> [LabelResult] {
        var results: [LabelResult] = []
        var i = 0
        while i < photos.count {
            let chunk = Array(photos[i..<min(i + Self.batchSize, photos.count)])
            i += Self.batchSize
            switch await request(photos: chunk, jwt: jwt, auto: false, audit: false) {
            case .ok(let r): results.append(contentsOf: r)
            case .quota: return results   // out of credits — stop spending, caller falls back
            case .failed: continue
            }
        }
        return results
    }

    /// Downscaled JPEG data URL straight off the file via CGImageSource —
    /// the full image is never decoded into memory.
    private static func jpegDataURL(relativePath: String, maxDim: Int = 1024, quality: CGFloat = 0.65) -> String? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = docs.appendingPathComponent(relativePath)
        let opts = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDim,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary
        guard let src = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, opts),
              let jpeg = UIImage(cgImage: thumb).jpegData(compressionQuality: quality) else { return nil }
        return "data:image/jpeg;base64," + jpeg.base64EncodedString()
    }
}
