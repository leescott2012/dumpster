import Foundation
import SwiftData

/// A caption suggestion — either tied to a specific dump or general/pool-level.
/// Captions can be favorited, banned (thumbs-down), and rated 0–5.
@Model
final class DumpCaption {

    @Attribute(.unique) var id: String
    var text: String
    var style: String             // "storytelling", "emoji", "clean", "numbered"
    var rating: Int               // 0–5
    var dumpId: String?           // Associated PhotoDump.id, or nil for pool-level
    var createdAt: Date
    var favorited: Bool
    var banned: Bool              // Thumbs-down → never use again

    init(
        id: String = "cap-\(Date.now.timeIntervalSince1970)-\(UUID().uuidString.prefix(8))",
        text: String,
        style: String = "clean",
        rating: Int = 0,
        dumpId: String? = nil,
        favorited: Bool = false,
        banned: Bool = false
    ) {
        self.id = id
        self.text = text
        self.style = style
        self.rating = rating
        self.dumpId = dumpId
        self.createdAt = Date()
        self.favorited = favorited
        self.banned = banned
    }
}
