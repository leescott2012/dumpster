import UIKit

/// Manages on-disk storage for imported photos. Originals are preserved
/// verbatim (full resolution, original format, EXIF) via `saveImageData`.
/// Files live under the app sandbox at `Documents/photos/<filename>`.
/// All paths returned/accepted are *relative* to Documents (e.g. "photos/abc.jpg")
/// so DumpPhoto.localPath stays portable across app launches.
final class PhotoStorageManager {

    static let shared = PhotoStorageManager()

    private let photosDir: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - Save

    /// Resolve a non-colliding filename within the photos dir.
    private func uniqueName(_ name: String) -> String {
        if FileManager.default.fileExists(atPath: photosDir.appendingPathComponent(name).path) {
            return "\(UUID().uuidString.prefix(8))_\(name)"
        }
        return name
    }

    /// Save raw image bytes to disk **verbatim** — full resolution, original
    /// format (HEIC/JPEG/PNG/…), and EXIF all preserved. No UIImage decode/
    /// re-encode (that would recompress and strip metadata). This is the
    /// preferred path for photos imported from PhotosPicker. Returns the
    /// relative path (e.g. `"photos/abc.heic"`), or nil if the write fails.
    @discardableResult
    func saveImageData(_ data: Data, filename: String? = nil) -> String? {
        let ext = Self.fileExtension(for: data)
        let base = filename.map { ($0 as NSString).deletingPathExtension } ?? UUID().uuidString
        let name = uniqueName("\(base).\(ext)")
        let fileURL = photosDir.appendingPathComponent(name)
        do {
            try data.write(to: fileURL)
        } catch {
            return nil
        }
        return "photos/\(name)"
    }

    /// Save a UIImage to disk as JPEG at **maximum quality (1.0)**. Use this
    /// only when the original encoded bytes aren't available (e.g. a UIImage
    /// from the camera or a render). For imported assets prefer
    /// `saveImageData`, which keeps the original quality, resolution, and EXIF.
    @discardableResult
    func saveImage(_ image: UIImage, filename: String? = nil) -> String {
        let name = uniqueName(filename ?? "\(UUID().uuidString).jpg")
        let fileURL = photosDir.appendingPathComponent(name)
        if let data = image.jpegData(compressionQuality: 1.0) {
            try? data.write(to: fileURL)
        }
        return "photos/\(name)"
    }

    /// Sniff the image format from magic bytes so saved files get a correct
    /// extension (and HEIC isn't mislabeled `.jpg`). Defaults to "jpg".
    private static func fileExtension(for data: Data) -> String {
        let b = [UInt8](data.prefix(16))
        guard b.count >= 12 else { return "jpg" }
        if b[0] == 0xFF, b[1] == 0xD8, b[2] == 0xFF { return "jpg" }                 // JPEG
        if b[0] == 0x89, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47 { return "png" }   // PNG
        if b[0] == 0x47, b[1] == 0x49, b[2] == 0x46 { return "gif" }                 // GIF
        if b[0] == 0x52, b[1] == 0x49, b[2] == 0x46, b[3] == 0x46,                   // RIFF…WEBP
           b[8] == 0x57, b[9] == 0x45, b[10] == 0x42, b[11] == 0x50 { return "webp" }
        if b[4] == 0x66, b[5] == 0x74, b[6] == 0x79, b[7] == 0x70 {                  // ftyp box
            let brand = String(bytes: b[8..<12], encoding: .ascii)?.lowercased() ?? ""
            if brand.hasPrefix("hei") || brand.hasPrefix("hev") ||
               brand.hasPrefix("mif") || brand.hasPrefix("msf") { return "heic" }
        }
        return "jpg"
    }

    // MARK: - Load

    /// Load a UIImage from a relative path produced by saveImage.
    func loadImage(relativePath: String) -> UIImage? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent(relativePath)
        return UIImage(contentsOfFile: url.path)
    }

    // MARK: - Delete

    /// Delete a photo file. No-op if the file no longer exists.
    func deleteImage(relativePath: String) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent(relativePath)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Diagnostics

    /// Total bytes used by the photos directory (rough — sums file sizes).
    func diskUsageBytes() -> Int64 {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: photosDir,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        return urls.reduce(0) { acc, url in
            acc + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
}
