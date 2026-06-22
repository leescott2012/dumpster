import Foundation
import SwiftData

/// A caption suggestion — either tied to a specific dump or general/pool-level.
/// Captions can be favorited, banned (thumbs-down), and rated 0–5.
///
/// Sync semantics (must match web captionPool.ts exactly):
/// - `deleted = true` is a tombstone — never removed from the record; propagates to all devices.
/// - `id` for seed captions must be generated via `DumpCaption.seedId(style:text:)` so all
///   devices produce the same ID for the same seed text (prevents duplicate accumulation on sync).
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
    /// Tombstone: true means the user deleted this caption.
    /// NEVER filtered out of storage — propagates to cloud so other devices learn about deletions.
    var deleted: Bool

    init(
        id: String = "cap-\(Int(Date.now.timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(8))",
        text: String,
        style: String = "clean",
        rating: Int = 0,
        dumpId: String? = nil,
        favorited: Bool = false,
        banned: Bool = false,
        deleted: Bool = false
    ) {
        self.id = id
        self.text = text
        self.style = style
        self.rating = rating
        self.dumpId = dumpId
        self.createdAt = Date()
        self.favorited = favorited
        self.banned = banned
        self.deleted = deleted
    }

    // MARK: - Deterministic Seed ID

    /// Produces the same ID as the web's `captionPool.ts:seedId(style, text)`.
    ///
    /// Algorithm: djb2 hash of `"style|text"`, base36-encoded, prefixed "seed-".
    /// Must stay byte-for-byte identical to the web implementation so cross-device
    /// dedup works via id-union (same seed on web and iOS → same id → no duplicate).
    static func seedId(style: String, text: String) -> String {
        let s = style + "|" + text
        var h: Int32 = 5381
        for scalar in s.unicodeScalars {
            // charCodeAt() in JS returns UTF-16 code units (0–65535).
            // For BMP characters, unicodeScalar.value equals the UTF-16 code unit.
            // All seed caption characters are BMP, so this is exact.
            let c = Int32(scalar.value & 0xFFFF)
            // Matches JS: ((h << 5) + h + c) | 0  — all wrapping Int32 arithmetic
            h = (h &<< 5) &+ h &+ c
        }
        // Use Int64 for abs() to handle the Int32.min edge case (-2147483648 has no positive Int32)
        // Matches JS Math.abs(h) which returns float64 and can represent 2147483648.
        let absVal = abs(Int64(h))
        return "seed-" + String(absVal, radix: 36)
    }
}
