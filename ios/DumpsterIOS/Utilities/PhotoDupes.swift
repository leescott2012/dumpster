import Foundation

/// Lightweight "possible duplicate" detection for the photo pool.
/// Direct port of client/src/lib/photoDupes.ts — keep the two in sync.
///
/// We can't hash pixels cheaply, so we lean on signals captured at import
/// time: byte-exact fileSize (+ pixel dimensions when available) catches a
/// re-imported file even after any re-encoding. A photo is flagged only when
/// it shares a signature with at least one OTHER photo.
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
        var byKey: [String: [String]] = [:]
        for photo in photos {
            guard let key = signature(photo) else { continue }
            byKey[key, default: []].append(photo.id)
        }
        var dupes: Set<String> = []
        for ids in byKey.values where ids.count > 1 {
            dupes.formUnion(ids)
        }
        return dupes
    }
}
