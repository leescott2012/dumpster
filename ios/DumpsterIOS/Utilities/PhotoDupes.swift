import Foundation
import ImageIO
import CoreGraphics

/// Lightweight "possible duplicate" detection for the photo pool.
/// Direct port of client/src/lib/photoDupes.ts — keep the two in sync.
///
/// Two signals, mirroring the web:
///   1. Byte signature captured at import time — byte-exact fileSize (+ pixel
///      dimensions) catches a re-imported file instantly.
///   2. Perceptual aHash (8×8 grayscale average hash) — catches photos that
///      LOOK identical but differ in bytes (re-encodes, saved-from-app copies).
///      Hashes compute off-main via `hashMissingPhotos`; the view bumps a
///      state counter when new hashes land so the dup set re-evaluates.
enum PhotoDupes {

    private static func signature(_ p: DumpPhoto) -> String? {
        if let size = p.fileSize {
            if let w = p.pixelWidth, let h = p.pixelHeight {
                return "s:\(size):\(w)x\(h)"
            }
            return "s:\(size)"
        }
        // No metadata (e.g. videos) — fall back to exact file identity.
        return "u:\(p.localPath)"
    }

    /// Ids of photos that look like duplicates of another photo in the given list.
    /// Pass the whole workspace (pool + every dump's photos) so a pooled photo
    /// that duplicates one already placed in a dump is still flagged.
    static func findDuplicateIds(_ photos: [DumpPhoto]) -> Set<String> {
        cacheLock.lock()
        let hashes = hashCache
        cacheLock.unlock()

        var byKey: [String: [String]] = [:]
        for photo in photos {
            if let key = signature(photo) {
                byKey[key, default: []].append(photo.id)
            }
            if let hash = hashes[photo.id], !hash.isEmpty {
                byKey["h:\(hash)", default: []].append(photo.id)
            }
        }
        var dupes: Set<String> = []
        for ids in byKey.values where ids.count > 1 {
            dupes.formUnion(ids)  // a photo in both an EXIF and a hash group dedupes here
        }
        return dupes
    }

    // MARK: - Perceptual hash

    private static let cacheLock = NSLock()
    private static var hashCache: [String: String] = [:]  // photo id → aHash ("" = failed, don't retry)

    /// Compute aHashes for photos not yet in the cache. Pass (id, relativePath)
    /// pairs extracted on the main actor (SwiftData models shouldn't cross
    /// concurrency domains). Returns true if any NEW hash landed — caller
    /// should then invalidate its dup set.
    static func hashMissingPhotos(_ items: [(id: String, relativePath: String)]) async -> Bool {
        var added = false
        for item in items {
            cacheLock.lock()
            let seen = hashCache[item.id] != nil
            cacheLock.unlock()
            if seen { continue }

            let hash = aHash(relativePath: item.relativePath) ?? ""
            cacheLock.lock()
            hashCache[item.id] = hash
            cacheLock.unlock()
            if !hash.isEmpty { added = true }
        }
        return added
    }

    /// 8×8 grayscale average hash of the image at Documents/<relativePath>.
    /// Uses CGImageSource thumbnailing so the full image is never decoded.
    private static func aHash(relativePath: String) -> String? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent(relativePath)
        let thumbOpts = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 8,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts) else { return nil }

        var pixels = [UInt8](repeating: 0, count: 64)
        guard let ctx = CGContext(
            data: &pixels, width: 8, height: 8,
            bitsPerComponent: 8, bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(thumb, in: CGRect(x: 0, y: 0, width: 8, height: 8))

        let avg = pixels.reduce(0) { $0 + Int($1) } / 64
        var hash = ""
        for i in stride(from: 0, to: 64, by: 4) {
            var nibble = 0
            for b in 0..<4 where Int(pixels[i + b]) >= avg { nibble |= 1 << b }
            hash += String(nibble, radix: 16)
        }
        return hash
    }
}
