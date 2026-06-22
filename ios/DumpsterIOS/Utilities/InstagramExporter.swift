import UIKit
import Photos

// MARK: - InstagramExporter
//
// Saves dump photos to Camera Roll in sequential order (so they appear
// as the most-recent photos in Instagram's picker), optionally copies
// the caption to clipboard, then deep-links into Instagram.

final class InstagramExporter {

    static let shared = InstagramExporter()
    private init() {}

    // MARK: - Public API

    /// Export a dump's photos to Camera Roll in order, copy caption, open Instagram.
    /// - Parameters:
    ///   - photos: Ordered array of DumpPhoto objects (already in dump sequence)
    ///   - caption: Optional caption string to copy to clipboard
    ///   - completion: Called on main thread with (success, errorMessage?)
    func exportToInstagram(
        photos: [DumpPhoto],
        caption: String?,
        completion: @escaping (Bool, String?) -> Void
    ) {
        var images = [UIImage]()
        for photo in photos {
            if let img = PhotoStorageManager.shared.loadImage(relativePath: photo.localPath) {
                images.append(img)
            }
        }

        guard !images.isEmpty else {
            completion(false, "No photos to export")
            return
        }

        // Request photo library access
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    completion(false, "Photo library access denied")
                }
                return
            }

            self.savePhotosSequentially(images: images) { success, error in
                DispatchQueue.main.async {
                    guard success else {
                        completion(false, error ?? "Failed to save photos")
                        return
                    }

                    // Copy caption to clipboard
                    if let caption = caption, !caption.isEmpty {
                        UIPasteboard.general.string = caption
                    }

                    // Open Instagram
                    self.openInstagram()

                    completion(true, nil)
                }
            }
        }
    }

    // MARK: - Private Helpers

    /// Save images to Camera Roll one at a time with slight timestamp offsets
    /// so they appear in the correct order in Instagram's recents.
    private func savePhotosSequentially(
        images: [UIImage],
        completion: @escaping (Bool, String?) -> Void
    ) {
        var savedCount = 0
        var lastError: Error?

        // Save each photo with a small time offset so ordering is preserved
        // Instagram shows most-recent first, so save in reverse order
        // (last photo saved = most recent = shown first in grid)
        // Actually, we save first-to-last with increasing timestamps.
        // Instagram carousel selection is left-to-right = oldest-to-newest.
        // So save photo 1 first (earliest timestamp), photo N last (latest timestamp).

        func saveNext(index: Int) {
            guard index < images.count else {
                completion(lastError == nil, lastError?.localizedDescription)
                return
            }

            PHPhotoLibrary.shared().performChanges({
                var request = PHAssetCreationRequest.forAsset()
                request.addResource(
                    with: .photo,
                    data: images[index].jpegData(compressionQuality: 0.95) ?? Data(),
                    options: nil
                )
                // Set creation date with offset so ordering is preserved
                request.creationDate = Date().addingTimeInterval(Double(index) * 0.5)
            }) { success, error in
                if success {
                    savedCount += 1
                } else {
                    lastError = error
                }
                // Small delay to ensure timestamp ordering
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                    saveNext(index: index + 1)
                }
            }
        }

        saveNext(index: 0)
    }

    /// Open Instagram app via deep link, or App Store if not installed.
    private func openInstagram() {
        var instagramURL = URL(string: "instagram://library")!
        if UIApplication.shared.canOpenURL(instagramURL) {
            UIApplication.shared.open(instagramURL)
        } else {
            // Fallback: open Instagram in App Store
            var appStoreURL = URL(string: "https://apps.apple.com/app/instagram/id389801252")!
            UIApplication.shared.open(appStoreURL)
        }
    }
}
