import Foundation
import SwiftData

/// A single photo in the user's pool. Persisted as a SwiftData entity.
/// The image bytes live on disk under Documents/photos/<localPath>.
@Model
final class DumpPhoto {

    @Attribute(.unique) var id: String
    var localPath: String        // Relative path within app's Documents/photos/
    var filename: String
    var category: String         // e.g. "AUTOMOTIVE", "PORTRAIT", "NIGHTLIFE"
    var labels: [String]         // Free-text labels (Vision output, multiple per photo)
    var starred: Bool
    var isHuji: Bool
    var createdAt: Date

    /// Computed: full URL to the image file inside the app sandbox.
    var imageURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(localPath)
    }

    init(
        id: String = "p-\(Date.now.timeIntervalSince1970)-\(UUID().uuidString.prefix(8))",
        localPath: String,
        filename: String,
        category: String = "LIFESTYLE",
        labels: [String] = [],
        starred: Bool = false,
        isHuji: Bool = false
    ) {
        self.id = id
        self.localPath = localPath
        self.filename = filename
        self.category = category
        self.labels = labels
        self.starred = starred
        self.isHuji = isHuji
        self.createdAt = Date()
    }
}
