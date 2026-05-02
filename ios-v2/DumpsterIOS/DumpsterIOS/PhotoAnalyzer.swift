import UIKit
import Vision

// MARK: - Models

struct AnalyzedPhoto {
    let image: UIImage
    let localURL: URL
    let filename: String
    let category: String
    let clusterKey: String
    let faceCount: Int
    /// Top Vision labels for this photo (used for caption generation).
    let labels: [String]
}

struct PhotoCluster {
    let title: String
    let category: String
    let photos: [AnalyzedPhoto]

    /// Aggregate all unique labels across photos in this cluster.
    var allLabels: [String] {
        let all = photos.flatMap { $0.labels }
        // Deduplicate while preserving order
        var seen = Set<String>()
        return all.filter { seen.insert($0).inserted }
    }
}

// MARK: - Photo Analyzer

class PhotoAnalyzer {

    // Map Vision labels → DUMPSTER categories (expanded for better matching)
    private static let categoryMap: [(keywords: [String], category: String, clusterKey: String)] = [
        (["car", "vehicle", "automobile", "truck", "motorcycle", "sports car", "racing",
          "lambo", "ferrari", "porsche", "rim", "wheel", "engine", "steering wheel",
          "dashboard", "sedan", "coupe", "convertible"],
         "AUTOMOTIVE", "automotive"),

        (["face", "person", "people", "man", "woman", "portrait", "selfie",
          "crowd", "human", "head", "smile", "hair"],
         "PORTRAIT", "portrait"),

        (["night", "dark", "bar", "club", "disco", "neon", "party", "drink",
          "alcohol", "cocktail", "beer", "wine", "concert", "stage", "light",
          "nightclub", "dance"],
         "NIGHTLIFE", "nightlife"),

        (["food", "meal", "restaurant", "pizza", "sushi", "dessert", "coffee",
          "dining", "plate", "table", "breakfast", "lunch", "dinner", "snack",
          "cuisine", "chef", "bakery"],
         "DINING", "dining"),

        (["gym", "fitness", "workout", "exercise", "sport", "running",
          "basketball", "training", "weights", "yoga", "athlete", "muscle"],
         "FITNESS", "fitness"),

        (["beach", "ocean", "sea", "travel", "vacation", "sunset", "mountain",
          "nature", "sky", "palm tree", "sand", "water", "landscape", "horizon",
          "tropical", "island", "coast", "lake", "forest"],
         "TRAVEL", "travel"),

        (["building", "architecture", "skyscraper", "hotel", "city", "urban",
          "interior", "house", "room", "design", "structure", "window",
          "bridge", "tower", "facade"],
         "ARCHITECTURE", "architecture"),

        (["art", "museum", "gallery", "painting", "sculpture", "exhibition",
          "drawing", "canvas", "creative", "mural", "graffiti"],
         "ART", "art"),

        (["fashion", "clothing", "outfit", "shoes", "style", "model", "dress",
          "shirt", "pants", "sneakers", "jewelry", "watch", "handbag",
          "sunglasses", "accessories"],
         "FASHION", "fashion"),

        (["studio", "music", "recording", "microphone", "concert", "instrument",
          "guitar", "piano", "drums", "audio", "headphones", "vinyl",
          "turntable", "speaker"],
         "STUDIO", "studio"),
    ]

    // MARK: - Analyze

    static func analyze(images: [(UIImage, URL)], completion: @escaping ([PhotoCluster]) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            var analyzed: [AnalyzedPhoto] = []
            let group = DispatchGroup()
            let lock = NSLock()
            let semaphore = DispatchSemaphore(value: 2)

            for (image, url) in images {
                semaphore.wait()
                group.enter()

                analyzeImage(image: image, url: url) { result in
                    lock.lock()
                    analyzed.append(result)
                    lock.unlock()
                    semaphore.signal()
                    group.leave()
                }
            }

            group.wait()

            // Build clusters
            var clusters: [String: [AnalyzedPhoto]] = [:]
            for photo in analyzed {
                clusters[photo.clusterKey, default: []].append(photo)
            }

            var result: [PhotoCluster] = clusters.compactMap { key, photos in
                guard !photos.isEmpty else { return nil }
                let category = photos[0].category
                let title = dumpTitle(for: key, photos: photos)
                return PhotoCluster(title: title, category: category, photos: photos)
            }

            // Sort by photo count (largest clusters first), limit to 5 clusters / 20 photos each
            result.sort { $0.photos.count > $1.photos.count }
            result = result.prefix(5).map { cluster in
                PhotoCluster(
                    title: cluster.title,
                    category: cluster.category,
                    photos: Array(cluster.photos.prefix(20))
                )
            }

            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: - Single Image Analysis

    private static func analyzeImage(image: UIImage, url: URL, completion: @escaping (AnalyzedPhoto) -> Void) {
        // Use CGImage-based handler as fallback if URL fails (temp files can be tricky)
        guard let cgImage = image.cgImage else {
            completion(AnalyzedPhoto(
                image: image, localURL: url, filename: url.lastPathComponent,
                category: "LIFESTYLE", clusterKey: "lifestyle", faceCount: 0, labels: []
            ))
            return
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        var topCategory = "LIFESTYLE"
        var topClusterKey = "lifestyle"
        var faceCount = 0
        var collectedLabels: [String] = []

        let classifyRequest = VNClassifyImageRequest { request, error in
            if let error {
                print("[PhotoAnalyzer] Classification error: \(error.localizedDescription)")
                return
            }
            guard let observations = request.results as? [VNClassificationObservation] else { return }

            // FIX: Raised confidence threshold from 0.01 to 0.10 for meaningful filtering.
            // At 0.01, nearly every label passes — producing noisy, unreliable classifications.
            // 0.10 strikes a balance between catching relevant labels and filtering noise.
            let filtered = observations.filter { $0.confidence > 0.10 }
            let topLabels = filtered.prefix(15).map { $0.identifier.lowercased() }
            collectedLabels = Array(topLabels)

            for (keywords, category, clusterKey) in categoryMap {
                if topLabels.contains(where: { label in
                    keywords.contains(where: { keyword in label.contains(keyword) })
                }) {
                    topCategory = category
                    topClusterKey = clusterKey
                    break
                }
            }
        }

        let faceRequest = VNDetectFaceRectanglesRequest { request, _ in
            faceCount = (request.results as? [VNFaceObservation])?.count ?? 0
        }

        do {
            try handler.perform([classifyRequest, faceRequest])
        } catch {
            print("[PhotoAnalyzer] Vision error for \(url.lastPathComponent): \(error)")
        }

        // Prioritize Portrait if faces are detected and current category is generic
        if faceCount >= 1 && (topClusterKey == "lifestyle" || topClusterKey == "fashion") {
            topCategory = "PORTRAIT"
            topClusterKey = "portrait"
        }

        // Add face info to labels if relevant
        if faceCount > 0 && !collectedLabels.contains("face") {
            collectedLabels.insert("face", at: 0)
        }

        completion(AnalyzedPhoto(
            image: image,
            localURL: url,
            filename: url.lastPathComponent,
            category: topCategory,
            clusterKey: topClusterKey,
            faceCount: faceCount,
            labels: collectedLabels
        ))
    }

    // MARK: - Dump Titles

    private static func dumpTitle(for key: String, photos: [AnalyzedPhoto]) -> String {
        let count = photos.count
        switch key {
        case "automotive":   return count > 3 ? "Luxury Flex: Cars & Vibes" : "The Whips"
        case "portrait":     return count > 4 ? "The Crew" : "Portraits"
        case "nightlife":    return count > 3 ? "Night Out: After Dark" : "Night Vibes"
        case "dining":       return count > 2 ? "Good Eats & Drinks" : "Dining"
        case "fitness":      return "Grind Season"
        case "travel":       return count > 3 ? "On The Road" : "Scenic Views"
        case "architecture": return "Architecture & Space"
        case "art":          return "Art & Culture"
        case "fashion":      return "The Fits"
        case "studio":       return "Studio Session"
        default:             return "Lifestyle"
        }
    }
}
