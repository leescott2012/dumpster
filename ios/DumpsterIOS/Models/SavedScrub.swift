import Foundation
import SwiftData

/// Persisted Instagram scrub. Auto-saved after every successful Apify+Claude
/// distill so the user can re-apply the style profile later without paying
/// for another scrub.
@Model
final class SavedScrub {

    @Attribute(.unique) var id: String
    /// Raw URL the user pasted, e.g. "https://www.instagram.com/cristiano/"
    var profileURL: String
    /// Extracted handle (without @ or trailing slash), e.g. "cristiano"
    var handle: String
    /// Claude-distilled aesthetic + verbal voice (used by caption tone).
    var styleDescription: String
    /// Claude-distilled engagement playbook — what WORKS for this creator.
    /// Empty string for scrubs persisted before Phase F.
    var engagementPlaybook: String
    /// Top hashtags from the analyzed posts.
    var hashtags: [String]
    /// How many posts Apify returned + Claude analyzed.
    var postsAnalyzed: Int
    /// When the scrub completed.
    var createdAt: Date

    init(
        profileURL: String,
        styleDescription: String,
        engagementPlaybook: String = "",
        hashtags: [String] = [],
        postsAnalyzed: Int = 0
    ) {
        self.id = UUID().uuidString
        self.profileURL = profileURL
        self.handle = SavedScrub.extractHandle(from: profileURL)
        self.styleDescription = styleDescription
        self.engagementPlaybook = engagementPlaybook
        self.hashtags = hashtags
        self.postsAnalyzed = postsAnalyzed
        self.createdAt = Date()
    }

    /// Parse "@cristiano" out of various URL shapes.
    static func extractHandle(from url: String) -> String {
        let cleaned = url
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
        guard let path = cleaned.split(separator: "/").dropFirst().first else {
            return cleaned
        }
        return String(path).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
