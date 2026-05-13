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
    /// The Claude-distilled 2-3 sentence aesthetic description.
    var styleDescription: String
    /// Top hashtags from the analyzed posts.
    var hashtags: [String]
    /// How many posts Apify actually returned + Claude analyzed.
    var postsAnalyzed: Int
    /// When the scrub completed.
    var createdAt: Date

    init(
        profileURL: String,
        styleDescription: String,
        hashtags: [String] = [],
        postsAnalyzed: Int = 0
    ) {
        self.id = UUID().uuidString
        self.profileURL = profileURL
        self.handle = SavedScrub.extractHandle(from: profileURL)
        self.styleDescription = styleDescription
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
