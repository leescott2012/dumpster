import UIKit

/// Manages on-disk JPEG storage for imported photos.
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

    /// Save a UIImage to disk as JPEG (quality 0.85). If the requested filename
    /// collides, a short UUID is prepended. Returns the relative path
    /// (e.g. `"photos/abc.jpg"`) suitable for storing on a DumpPhoto.
    @discardableResult
    func saveImage(_ image: UIImage, filename: String? = nil) -> String {
        let name = filename ?? "\(UUID().uuidString).jpg"

        // Ensure unique filename
        let uniqueName: String
        if FileManager.default.fileExists(atPath: photosDir.appendingPathComponent(name).path) {
            uniqueName = "\(UUID().uuidString.prefix(8))_\(name)"
        } else {
            uniqueName = name
        }

        let fileURL = photosDir.appendingPathComponent(uniqueName)
        if let data = image.jpegData(compressionQuality: 0.85) {
            try? data.write(to: fileURL)
        }
        return "photos/\(uniqueName)"
    }

    /// Save raw image data (e.g. from PhotosPicker) without an intermediate
    /// UIImage round-trip. Same return contract as saveImage.
    @discardableResult
    func saveImageData(_ data: Data, filename: String? = nil) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        return saveImage(image, filename: filename)
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
