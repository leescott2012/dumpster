import AVFoundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Device-only video file handling. NOTHING here touches the network.
enum VideoStore {

    static let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    static let dir: URL = {
        let d = docs.appendingPathComponent("videos", isDirectory: true)
        try? FileManager.default.createDirectory(at: d.appendingPathComponent("thumbs", isDirectory: true),
                                                 withIntermediateDirectories: true)
        return d
    }()

    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]

    /// Cloud/AI guard: true for any path/filename that looks like a video, or lives in
    /// Documents/videos. Image-payload builders must refuse these.
    static func isVideoPath(_ path: String) -> Bool {
        path.hasPrefix("videos/") || videoExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    static func newFileURL(ext: String) -> URL {
        dir.appendingPathComponent("\(UUID().uuidString).\(ext.isEmpty ? "mov" : ext.lowercased())")
    }

    private static func rel(_ url: URL) -> String { "videos/" + url.lastPathComponent }

    /// Build a pool item from a file ALREADY inside `dir` (duration + downscaled first-frame thumb).
    static func makeItem(fileURL: URL, name: String, knownDuration: Double? = nil) async -> VideoItem {
        let asset = AVURLAsset(url: fileURL)
        var dur = knownDuration ?? 0
        if knownDuration == nil, let d = try? await asset.load(.duration) { dur = d.seconds }
        let id = UUID().uuidString
        var thumbRel = ""
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 480, height: 480)   // downscaled; never full-res
        let t = CMTime(seconds: dur.isFinite && dur > 0 ? min(0.1, dur / 2) : 0, preferredTimescale: 600)
        if let cg = try? await gen.image(at: t).image,
           let jpeg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.7) {
            let tURL = dir.appendingPathComponent("thumbs/\(id).jpg")
            if (try? jpeg.write(to: tURL)) != nil { thumbRel = "videos/thumbs/\(id).jpg" }
        }
        let item = VideoItem(id: id, name: name, relativePath: rel(fileURL), thumbPath: thumbRel,
                             duration: dur.isFinite ? dur : 0)
        item.tags = await autoTags(id: item.id, thumbPath: item.thumbPath, thumbURL: item.thumbURL)
        return item
    }

    /// Label a video from its thumbnail. OWNER EXCEPTION (Lee, 2026-10-25): the ≤480px poster
    /// still — never the video — may go to the paid label scan (1 credit, Claude Vision) for
    /// accurate labels. Signed out / out of credits / offline → on-device Apple Vision instead.
    static func autoTags(id: String, thumbPath: String, thumbURL: URL?, allowCloud: Bool = true) async -> [String] {
        guard let url = thumbURL else { return [] }
        if allowCloud, !thumbPath.isEmpty, let jwt = await MainActor.run(body: { AuthManager.shared.jwt }),
           let r = await LabelService.shared.label(photos: [(id: id, relativePath: thumbPath)], jwt: jwt).first {
            let label = r.label.count > 32 ? String(r.label.prefix(32)) : r.label
            return [r.category.capitalized, label].filter { !$0.isEmpty }
        }
        return await Task.detached(priority: .utility) {
            guard let img = UIImage(contentsOfFile: url.path) else { return [String]() }
            let r = PhotoAnalyzer.classifySingle(image: img)
            var out = [r.category.capitalized]
            for l in r.labels where out.count < 4 && !out.contains(where: { $0.lowercased() == l }) { out.append(l.capitalized) }
            return out
        }.value
    }

    static func deleteFiles(_ v: VideoItem) {
        try? FileManager.default.removeItem(at: v.fileURL)
        if let t = v.thumbURL { try? FileManager.default.removeItem(at: t) }
    }

    /// Copy a Files-picker URL into the pool dir (streamed copy, never loaded into memory).
    static func importFile(at src: URL) -> URL? {
        let scoped = src.startAccessingSecurityScopedResource()
        defer { if scoped { src.stopAccessingSecurityScopedResource() } }
        let dest = newFileURL(ext: src.pathExtension)
        do { try FileManager.default.copyItem(at: src, to: dest); return dest } catch { return nil }
    }

    // MARK: - Trimmed copy

    enum ExportError: LocalizedError {
        case unsupported, failed(String)
        var errorDescription: String? {
            switch self {
            case .unsupported: return "This video can't be exported."
            case .failed(let m): return m
            }
        }
    }

    /// Export [start, end] into a NEW file in the pool dir. Passthrough when possible, else HighestQuality.
    static func exportTrimmed(source: URL, start: Double, end: Double,
                              onProgress: @escaping (Double) -> Void) async throws -> (url: URL, duration: Double) {
        let asset = AVURLAsset(url: source)
        let presets = AVAssetExportSession.exportPresets(compatibleWith: asset)
        let preset = presets.contains(AVAssetExportPresetPassthrough) ? AVAssetExportPresetPassthrough
                                                                      : AVAssetExportPresetHighestQuality
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw ExportError.unsupported }
        let type: AVFileType = session.supportedFileTypes.contains(.mov) ? .mov
                             : (session.supportedFileTypes.contains(.mp4) ? .mp4 : (session.supportedFileTypes.first ?? .mov))
        let dest = newFileURL(ext: type == .mp4 ? "mp4" : "mov")
        session.outputURL = dest
        session.outputFileType = type
        session.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                        end: CMTime(seconds: end, preferredTimescale: 600))
        let poll = Task {
            while !Task.isCancelled {
                onProgress(Double(session.progress))
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
        defer { poll.cancel() }
        // ponytail: exportAsynchronously is deprecated on iOS 18 but works on the 17.0 target; swap to export(to:as:) when min target is 18.
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { c.resume() }
        }
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: dest)
            throw ExportError.failed(session.error?.localizedDescription ?? "Export failed.")
        }
        onProgress(1)
        return (dest, end - start)
    }
}

/// PhotosPicker transferable: streams the movie to a file inside the pool dir (no Data in memory).
struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { m in SentTransferredFile(m.url) }
        importing: { received in
            let dest = VideoStore.newFileURL(ext: received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedMovie(url: dest)
        }
    }
}
