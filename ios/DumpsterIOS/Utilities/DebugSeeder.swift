#if DEBUG
import SwiftUI
import SwiftData
import UIKit

/// One-shot helper that, when the SwiftData store is empty, drops in a sample
/// PhotoDump + 8 colored placeholder photos so visual QC has something to render.
/// Compiled out of release builds.
enum DebugSeeder {

    /// Returns true if it actually inserted data.
    @MainActor
    @discardableResult
    static func seedIfEmpty(context: ModelContext) -> Bool {
        let dumpFetch = FetchDescriptor<PhotoDump>()
        let photoFetch = FetchDescriptor<DumpPhoto>()
        let existingDumps = (try? context.fetch(dumpFetch)) ?? []
        let existingPhotos = (try? context.fetch(photoFetch)) ?? []
        guard existingDumps.isEmpty && existingPhotos.isEmpty else { return false }

        let palettes: [(name: String, category: String, color: UIColor)] = [
            ("portrait_01", "Portrait",   UIColor(red: 0.32, green: 0.40, blue: 0.55, alpha: 1)),
            ("auto_02",     "Automotive", UIColor(red: 0.55, green: 0.34, blue: 0.20, alpha: 1)),
            ("auto_03",     "Automotive", UIColor(red: 0.65, green: 0.18, blue: 0.18, alpha: 1)),
            ("studio_04",   "Studio",     UIColor(red: 0.18, green: 0.22, blue: 0.28, alpha: 1)),
            ("city_05",     "City",       UIColor(red: 0.26, green: 0.28, blue: 0.34, alpha: 1)),
            ("night_06",    "Night",      UIColor(red: 0.10, green: 0.10, blue: 0.14, alpha: 1)),
            ("portrait_07", "Portrait",   UIColor(red: 0.45, green: 0.32, blue: 0.40, alpha: 1)),
            ("studio_08",   "Studio",     UIColor(red: 0.30, green: 0.24, blue: 0.18, alpha: 1)),
        ]

        var dumpPhotoIDs: [String] = []
        var poolOnlyIDs: [String] = []

        for (idx, p) in palettes.enumerated() {
            let img = makePlaceholder(color: p.color, label: "\(idx + 1)", size: CGSize(width: 600, height: 800))
            let relPath = PhotoStorageManager.shared.saveImage(img, filename: "\(p.name).jpg")
            let dp = DumpPhoto(
                localPath: relPath,
                filename: "\(p.name).jpg",
                category: p.category,
                labels: ["sample", p.category.lowercased()],
                isHuji: idx == 1
            )
            if idx == 0 { dp.starred = true }
            context.insert(dp)
            if idx < 5 { dumpPhotoIDs.append(dp.id) }
            else       { poolOnlyIDs.append(dp.id) }
        }

        let dump = PhotoDump(
            num: 1,
            title: "The Creative's Saturday",
            photoIDs: dumpPhotoIDs,
            vibeBadge: nil,
            liked: false,
            titleApproved: true
        )
        context.insert(dump)
        _ = poolOnlyIDs

        try? context.save()
        return true
    }

    private static func makePlaceholder(color: UIColor, label: String, size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 220, weight: .heavy),
                .foregroundColor: UIColor.white.withAlphaComponent(0.6)
            ]
            let str = NSAttributedString(string: label, attributes: attrs)
            let strSize = str.size()
            let rect = CGRect(
                x: (size.width - strSize.width) / 2,
                y: (size.height - strSize.height) / 2,
                width: strSize.width,
                height: strSize.height
            )
            str.draw(in: rect)
        }
    }
}
#endif
