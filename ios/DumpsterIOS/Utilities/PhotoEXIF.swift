import Foundation
import ImageIO
import CoreLocation
import UniformTypeIdentifiers

/// EXIF / photo-metadata extraction (NATIVE_PORT.md §B).
/// Port of client/src/lib/exif.ts — reads straight off the ORIGINAL bytes via
/// ImageIO, so no PHAsset / Photo Library permission is required (the bytes
/// already contain any EXIF the source image had; PhotoStorageManager saves
/// them verbatim as of 158bc07).
///
/// Privacy: GPS is stored on-device alongside the photo and fed to AI prompts
/// like the web app does. Never logged or sent to Sentry/analytics.
enum PhotoEXIF {

    /// Populate a DumpPhoto's metadata fields in place from its original bytes.
    /// Best-effort and non-throwing — a photo with no EXIF (screenshot, PNG,
    /// re-saved image) just keeps its fields nil, same as the web behavior.
    static func populate(_ photo: DumpPhoto, from data: Data) {
        photo.fileSize = data.count

        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return }

        if let type = CGImageSourceGetType(source) as String? {
            photo.imageFormat = formatName(forUTI: type)
        }

        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return }

        if let w = props[kCGImagePropertyPixelWidth] as? Int { photo.pixelWidth = w }
        if let h = props[kCGImagePropertyPixelHeight] as? Int { photo.pixelHeight = h }
        if let orientation = props[kCGImagePropertyOrientation] as? Int { photo.orientation = orientation }

        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
            applyGPS(gps, to: photo)
        }

        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            applyExif(exif, to: photo)
        }

        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            applyTIFF(tiff, to: photo)
        }
    }

    // MARK: - Format

    private static func formatName(forUTI uti: String) -> String {
        switch uti {
        case UTType.heic.identifier, UTType.heif.identifier: return "HEIF"
        case UTType.jpeg.identifier: return "JPEG"
        case UTType.png.identifier: return "PNG"
        case UTType.webP.identifier: return "WEBP"
        case UTType.gif.identifier: return "GIF"
        default: return uti
        }
    }

    // MARK: - GPS

    private static func applyGPS(_ gps: [CFString: Any], to photo: DumpPhoto) {
        guard let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
              let lng = gps[kCGImagePropertyGPSLongitude] as? Double else { return }
        let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String
        let lngRef = gps[kCGImagePropertyGPSLongitudeRef] as? String
        photo.lat = (latRef == "S") ? -lat : lat
        photo.lng = (lngRef == "W") ? -lng : lng
    }

    // MARK: - Exif

    private static let exifDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static func applyExif(_ exif: [CFString: Any], to photo: DumpPhoto) {
        let takenString = (exif[kCGImagePropertyExifDateTimeOriginal] as? String)
            ?? (exif[kCGImagePropertyExifDateTimeDigitized] as? String)
        if let takenString, let date = exifDateFormatter.date(from: takenString) {
            photo.takenAt = date
        }

        if let lensModel = exif[kCGImagePropertyExifLensModel] as? String {
            photo.lens = lensModel.trimmingCharacters(in: .whitespaces)
        }

        if let isoArray = exif[kCGImagePropertyExifISOSpeedRatings] as? [Int], let iso = isoArray.first {
            photo.iso = iso
        }

        // Prefer 35mm-equivalent focal length when available (matches what iOS shows elsewhere).
        if let fl35 = exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? Double {
            photo.focalLength = fl35
        } else if let fl = exif[kCGImagePropertyExifFocalLength] as? Double {
            photo.focalLength = fl
        }

        if let fNumber = exif[kCGImagePropertyExifFNumber] as? Double { photo.fStop = fNumber }
        if let exposure = exif[kCGImagePropertyExifExposureTime] as? Double { photo.shutterSpeed = exposure }
    }

    // MARK: - TIFF (camera make/model)

    private static func applyTIFF(_ tiff: [CFString: Any], to photo: DumpPhoto) {
        let make = (tiff[kCGImagePropertyTIFFMake] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let model = (tiff[kCGImagePropertyTIFFModel] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !make.isEmpty || !model.isEmpty else { return }
        // De-duplicate ("Apple Apple iPhone 14" -> "Apple iPhone 14"), matching web.
        if model.lowercased().hasPrefix(make.lowercased()) {
            photo.camera = model
        } else {
            photo.camera = [make, model].filter { !$0.isEmpty }.joined(separator: " ")
        }
    }
}

/// On-device place naming. Privacy: coordinates go ONLY to Apple's own reverse geocoder
/// (CLGeocoder, the OS location service) -- never to our server, Apify or any third-party
/// geocoder -- and only the resulting place TEXT is stored/fed to AI prompts.
@MainActor
final class PlaceNamer {
    static let shared = PlaceNamer()
    private let geocoder = CLGeocoder()
    private var cache: [String: String] = [:]   // rounded coordinate -> place text ("" = none found)
    private var lastCall = Date.distantPast
    private var running = false

    /// Fills `placeName` for photos that have GPS but no name yet. Serialized and
    /// throttled (Apple limits geocoder requests); failures are silent and retried next launch.
    func fill(_ photos: [DumpPhoto]) async {
        guard !running else { return }
        running = true
        defer { running = false }
        for photo in photos where photo.placeName == nil {
            guard let lat = photo.lat, let lng = photo.lng else { continue }
            let key = String(format: "%.3f,%.3f", lat, lng)   // ~110 m
            if let hit = cache[key] {
                if !hit.isEmpty { photo.placeName = hit }
                continue
            }
            // >= 1.5 s between lookups (~40/min, under Apple's 50/min cap).
            let wait = 1.5 - Date().timeIntervalSince(lastCall)
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            lastCall = Date()
            do {
                let marks = try await geocoder.reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lng))
                let name = marks.first.flatMap(Self.describe) ?? ""
                cache[key] = name
                if !name.isEmpty { photo.placeName = name }
            } catch {
                // Throttled / offline: stop quietly, try again next time.
                if let code = (error as? CLError)?.code, code == .network { return }
            }
        }
    }

    /// "Venue, City" when Apple knows a point of interest, else "Neighborhood, City".
    static func describe(_ m: CLPlacemark) -> String? {
        let area = m.locality ?? m.administrativeArea
        let first = m.areasOfInterest?.first ?? m.subLocality
        var out: [String] = []
        for p in [first, area].compactMap({ $0 }) where !p.isEmpty && out.last != p { out.append(p) }
        return out.isEmpty ? nil : out.joined(separator: ", ")
    }
}
