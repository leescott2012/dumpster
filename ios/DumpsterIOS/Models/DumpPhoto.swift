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

    // MARK: - EXIF / Photo metadata (NATIVE_PORT.md §5)
    // Extract via PHAsset / ImageIO BEFORE any downsample — downsampling strips EXIF.
    // Persisted so subsequent sessions still have it without re-reading from the asset.
    var takenAt: Date?           // EXIF DateTimeOriginal
    var lat: Double?             // GPS latitude
    var lng: Double?             // GPS longitude
    var camera: String?          // e.g. "iPhone 14 Pro"
    var lens: String?            // e.g. "iPhone 14 Pro back triple camera 6.86mm f/2.8"
    var iso: Int?
    var focalLength: Double?     // mm
    var fStop: Double?           // e.g. 2.8
    var shutterSpeed: Double?    // seconds (e.g. 0.00025)
    var imageFormat: String?     // "HEIF", "JPEG", "PNG", etc.
    var orientation: Int?        // EXIF orientation 1–8
    var pixelWidth: Int?
    var pixelHeight: Int?
    var fileSize: Int?           // bytes

    /// Computed: full URL to the image file inside the app sandbox.
    var imageURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(localPath)
    }

    /// One-line summary injected into AI prompts, matching web's metaLine() format.
    /// e.g. "[taken 2024-09-12 14:32 · iPhone 14 Pro · 37.78,-122.41]"
    var metaLine: String? {
        var parts: [String] = []
        if let d = takenAt {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd HH:mm"
            parts.append("taken \(fmt.string(from: d))")
        }
        if let cam = camera { parts.append(cam) }
        if let la = lat, let lo = lng {
            parts.append(String(format: "%.2f,%.2f", la, lo))
        }
        guard !parts.isEmpty else { return nil }
        return "[" + parts.joined(separator: " · ") + "]"
    }

    init(
        id: String = "p-\(Int(Date.now.timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(8))",
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
