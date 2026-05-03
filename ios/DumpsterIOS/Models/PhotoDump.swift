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
    var titleApproved: Bool?      // true = kept, false = rejected, nil = untouched
    var createdAt: Date

    init(
        id: String = "d-\(Date.now.timeIntervalSince1970)",
        num: Int,
        title: String = "Untitled Dump",
        photoIDs: [String] = [],
        vibeBadge: String? = nil,
        liked: Bool = false,
        titleApproved: Bool? = nil
    ) {
        self.id = id
        self.num = num
        self.title = title
        self.photoIDs = photoIDs
        self.vibeBadge = vibeBadge
        self.liked = liked
        self.titleApproved = titleApproved
        self.createdAt = Date()
    }
}
