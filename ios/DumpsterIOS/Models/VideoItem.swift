import Foundation
import SwiftData

/// A device-only Video Pool entry. HARD RULE (owner): videos are NEVER uploaded,
/// synced, or sent to any AI/API. Nothing network-facing may reference this type
/// or `VideoStore.dir`. The file lives under Documents/videos/ (relative paths,
/// same convention as DumpPhoto.localPath); trim is non-destructive.
@Model
final class VideoItem {
    @Attribute(.unique) var id: String
    var name: String
    var relativePath: String      // "videos/<uuid>.mov"
    var thumbPath: String         // "videos/thumbs/<uuid>.jpg" ("" if extraction failed)
    var duration: Double          // seconds
    var tags: [String]            // Outfit / Travel / Car / Other + free text
    var trimStart: Double?        // seconds; nil = untrimmed
    var trimEnd: Double?
    var addedAt: Date

    init(id: String = UUID().uuidString, name: String, relativePath: String,
         thumbPath: String, duration: Double) {
        self.id = id
        self.name = name
        self.relativePath = relativePath
        self.thumbPath = thumbPath
        self.duration = duration
        self.tags = []
        self.addedAt = Date()
    }

    var fileURL: URL { VideoStore.docs.appendingPathComponent(relativePath) }
    var thumbURL: URL? { thumbPath.isEmpty ? nil : VideoStore.docs.appendingPathComponent(thumbPath) }

    /// Effective [start, end] seconds (trim or full length). Mirrors web trimRange().
    var range: (start: Double, end: Double) {
        let s = trimStart ?? 0
        let e = (trimEnd ?? 0) > s ? trimEnd! : duration
        return (s, e)
    }
    var isTrimmed: Bool { trimStart != nil || trimEnd != nil }
    var shownLength: Double { range.end - range.start }
}

func fmtTime(_ sec: Double) -> String {
    let t = max(0, Int(sec.rounded()))
    return String(format: "%02d:%02d", t / 60, t % 60)
}
