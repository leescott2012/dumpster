import Foundation
import SwiftData

/// A single carousel "dump" — an ordered set of up to ~20 photos with a title.
/// `photoIDs` references DumpPhoto.id values; resolution is done at the view layer.
@Model
final class PhotoDump {

    @Attribute(.unique) var id: String
    var num: Int
    var title: String
    var photoIDs: [String]        // Ordered. Cap at 20 photos per Instagram carousel limit.
    var vibeBadge: String?        // nil or "mismatch"
    var liked: Bool
    var isAIGenerated: Bool       // true = created by AUTO-GENERATE
    var titleApproved: Bool?      // true = kept, false = rejected, nil = untouched
    var rating: String?           // "up" | "down" | nil — mirrors web Dump.rating
    var archived: Bool = false    // hidden from the main list, restorable (mirrors web archive)
    var createdAt: Date

    init(
        id: String = "d-\(Date.now.timeIntervalSince1970)",
        num: Int,
        title: String = "Untitled Dump",
        photoIDs: [String] = [],
        vibeBadge: String? = nil,
        liked: Bool = false,
        isAIGenerated: Bool = false,
        titleApproved: Bool? = nil,
        rating: String? = nil,
        archived: Bool = false
    ) {
        self.id = id
        self.num = num
        self.title = title
        self.photoIDs = photoIDs
        self.vibeBadge = vibeBadge
        self.liked = liked
        self.isAIGenerated = isAIGenerated
        self.titleApproved = titleApproved
        self.rating = rating
        self.archived = archived
        self.createdAt = Date()
    }
}
