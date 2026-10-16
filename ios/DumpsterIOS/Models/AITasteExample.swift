import Foundation
import SwiftData

/// On-device AI taste memory. Each record captures a snapshot of a dump
/// the user loved (hearted) or skipped/deleted, so auto-gen can learn
/// their personal aesthetic over time.
@Model
final class AITasteExample {

    @Attribute(.unique) var id: String
    var isPositive: Bool        // true = hearted, false = deleted/skipped
    var categories: [String]    // dominant categories, e.g. ["NIGHTLIFE","AUTOMOTIVE"]
    var photoCount: Int
    var vibe: String            // vibe word from last AI caption, e.g. "moody"
    var captionStyle: String    // e.g. "Aesthetic"
    var dumpTitle: String
    var createdAt: Date

    init(
        isPositive: Bool,
        categories: [String],
        photoCount: Int,
        vibe: String = "",
        captionStyle: String = "",
        dumpTitle: String = ""
    ) {
        self.id = UUID().uuidString
        self.isPositive = isPositive
        self.categories = categories
        self.photoCount = photoCount
        self.vibe = vibe
        self.captionStyle = captionStyle
        self.dumpTitle = dumpTitle
        self.createdAt = Date()
    }

    /// Compact description injected into the AI system prompt.
    var promptDescription: String {
        let sentiment = isPositive ? "✓ LOVED" : "✗ SKIPPED"
        let cats = categories.prefix(3).joined(separator: "+")
        let vibeStr = vibe.isEmpty ? "" : ", \(vibe) vibe"
        return "\(sentiment): \(photoCount) photos, \(cats)\(vibeStr)"
    }
}

// MARK: - Taste Profile Builder

extension AITasteExample {

    /// Build a snapshot from a dump + its resolved photos.
    static func from(dump: PhotoDump, photos: [DumpPhoto], isPositive: Bool) -> AITasteExample {
        var counts: [String: Int] = [:]
        for p in photos { counts[p.category.uppercased(), default: 0] += 1 }
        let topCats = counts.sorted { $0.value > $1.value }.map { $0.key }
        let style = UserDefaults.standard.string(forKey: "llm_caption_style") ?? "casual"
        return AITasteExample(
            isPositive: isPositive,
            categories: Array(topCats.prefix(4)),
            photoCount: photos.count,
            captionStyle: style,
            dumpTitle: dump.title
        )
    }

    /// Generate the system-prompt injection block from up to 10 recent examples.
    static func promptBlock(from examples: [AITasteExample]) -> String {
        guard !examples.isEmpty else { return "" }
        let recent = Array(examples.sorted { $0.createdAt > $1.createdAt }.prefix(10))
        let lines = recent.map { $0.promptDescription }.joined(separator: "\n")
        return """

        User's proven taste examples (learn from these):
        \(lines)
        """
    }
}

// MARK: - Caption voice + confirmed taste preferences (web: buildTasteBlock / appendTastePreference)

extension AITasteExample {

    /// Favorite + banned caption lines for the taste block (≤8 each, like web).
    /// Tombstoned (deleted) captions still count as banned when flagged.
    @MainActor
    static func captionVoiceBlock() -> String {
        guard let ctx = ModelContextHolder.shared.context else { return "" }
        var fav = FetchDescriptor<DumpCaption>(predicate: #Predicate { $0.favorited && !$0.deleted })
        fav.fetchLimit = 8
        var ban = FetchDescriptor<DumpCaption>(predicate: #Predicate { $0.banned })
        ban.fetchLimit = 8
        let favorites = ((try? ctx.fetch(fav)) ?? []).map { "- " + $0.text }
        let banned = ((try? ctx.fetch(ban)) ?? []).map { "- " + $0.text }
        var parts: [String] = []
        if !favorites.isEmpty { parts.append("User's favorite caption examples (match this voice):\n" + favorites.joined(separator: "\n")) }
        if !banned.isEmpty { parts.append("NEVER USE these patterns or anything similar:\n" + banned.joined(separator: "\n")) }
        return parts.isEmpty ? "" : "\n\n" + parts.joined(separator: "\n\n")
    }

    /// Single line, no control chars, capped — model output is untrusted.
    static func cleanTastePreference(_ raw: String) -> String {
        let noCtl = raw.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }.joined()
        let collapsed = noCtl.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return String(collapsed.prefix(AIProfileLimits.tastePrefMax))
    }

    enum TasteSaveResult { case saved, duplicate, full, empty }

    /// Append a user-confirmed preference to the Taste Profile (deduped, never past the max).
    static func appendTastePreference(_ raw: String) -> TasteSaveResult {
        let pref = cleanTastePreference(raw)
        guard !pref.isEmpty else { return .empty }
        let key = "ai_style_profile"
        let current = (UserDefaults.standard.string(forKey: key) ?? "")
            .replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        let lines = current.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        if lines.contains(pref.lowercased()) { return .duplicate }
        let next = current.isEmpty ? pref : current + "\n" + pref
        if next.count > AIProfileLimits.tasteProfileMax { return .full }
        UserDefaults.standard.set(next, forKey: key)
        return .saved
    }
}
