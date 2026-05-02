import WebKit
import UIKit

// MARK: - Custom URL Scheme Handler

/// Serves the bundled React web app and AI-generated photo thumbnails via the `dumpster://` scheme.
/// Handles three route types:
///   - `dumpster://app/photos` — JSON list of bundled sample photos
///   - `dumpster://app/ai/<filename>` — Vision-analyzed temp photo thumbnails
///   - `dumpster://app/*` — static files from the dist/ bundle (with SPA fallback)

class DumpsterSchemeHandler: NSObject, WKURLSchemeHandler {

    // MARK: - Properties

    /// Pre-built map of lowercase filenames/paths → file URLs in the dist bundle.
    private var fileMap: [String: URL] = [:]

    /// Track active scheme tasks to avoid responding to cancelled requests.
    /// WKURLSchemeTask does not have a `isCancelled` property, so we track manually.
    private var activeTasks = Set<ObjectIdentifier>()
    private let taskLock = NSLock()

    // MARK: - Init

    override init() {
        super.init()
        buildFileMap()
    }

    private func buildFileMap() {
        guard let distURL = Bundle.main.resourceURL?.appendingPathComponent("dist") else {
            print("[DumpsterScheme] Warning: dist/ folder not found in bundle")
            return
        }

        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: distURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let fileURL as URL in enumerator {
            let filename = fileURL.lastPathComponent.lowercased()
            fileMap[filename] = fileURL

            // Also store by relative path from 'dist/'
            let relativePath = fileURL.path.replacingOccurrences(of: distURL.path, with: "")
            let cleanPath = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
            if !cleanPath.isEmpty {
                fileMap[cleanPath.lowercased()] = fileURL
            }
        }

        print("[DumpsterScheme] Indexed \(fileMap.count) files from dist/")
    }

    // MARK: - Task Tracking

    private func trackTask(_ task: WKURLSchemeTask) {
        taskLock.lock()
        activeTasks.insert(ObjectIdentifier(task as AnyObject))
        taskLock.unlock()
    }

    private func untrackTask(_ task: WKURLSchemeTask) {
        taskLock.lock()
        activeTasks.remove(ObjectIdentifier(task as AnyObject))
        taskLock.unlock()
    }

    private func isTaskActive(_ task: WKURLSchemeTask) -> Bool {
        taskLock.lock()
        let active = activeTasks.contains(ObjectIdentifier(task as AnyObject))
        taskLock.unlock()
        return active
    }

    // MARK: - WKURLSchemeHandler

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        trackTask(urlSchemeTask)

        guard let url = urlSchemeTask.request.url else {
            failTask(urlSchemeTask, code: 400, message: "Missing URL")
            return
        }

        let path = url.path

        // Route: /photos — return JSON list of sample photos in the bundle
        if path.lowercased() == "/photos" || path.lowercased() == "/photos/" {
            handlePhotosEndpoint(task: urlSchemeTask, url: url)
            return
        }

        // Route: /ai/<filename> — serve Vision-analyzed temp photos
        if path.lowercased().hasPrefix("/ai/") {
            handleAIPhotoEndpoint(task: urlSchemeTask, url: url, path: path)
            return
        }

        // Route: static files from the bundle
        serveBundle(path: path, task: urlSchemeTask)
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // FIX: Mark the task as cancelled so async handlers don't crash
        untrackTask(urlSchemeTask)
    }

    // MARK: - /photos Endpoint

    private func handlePhotosEndpoint(task: WKURLSchemeTask, url: URL) {
        var photoList: [[String: String]] = []
        var seenURLs = Set<String>()

        for (key, fileURL) in fileMap {
            let ext = fileURL.pathExtension.lowercased()
            guard ["jpg", "jpeg", "png", "webp", "heic"].contains(ext) else { continue }
            guard key.contains("sample") || key.contains("photo") else { continue }

            let photoURL = "dumpster://app/\(key)"
            guard !seenURLs.contains(photoURL) else { continue }
            seenURLs.insert(photoURL)

            photoList.append([
                "url": photoURL,
                "name": fileURL.lastPathComponent
            ])
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: photoList) {
            respond(task: task, url: url, data: jsonData, mimeType: "application/json")
        } else {
            respond(task: task, url: url, data: Data("[]".utf8), mimeType: "application/json")
        }
    }

    // MARK: - /ai/ Endpoint

    private func handleAIPhotoEndpoint(task: WKURLSchemeTask, url: URL, path: String) {
        let filename = String(path.dropFirst("/ai/".count))
        let decoded = filename.removingPercentEncoding ?? filename
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dumpster_ai")
            .appendingPathComponent(decoded)

        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self, self.isTaskActive(task) else { return }

            if let data = try? Data(contentsOf: tempURL) {
                DispatchQueue.main.async {
                    guard self.isTaskActive(task) else { return }
                    self.respond(task: task, url: url, data: data, mimeType: "image/jpeg")
                }
            } else {
                DispatchQueue.main.async {
                    guard self.isTaskActive(task) else { return }
                    self.failTask(task, code: 404, message: "AI photo not found: \(decoded)")
                }
            }
        }
    }

    // MARK: - Static File Serving

    private func serveBundle(path: String, task: WKURLSchemeTask) {
        let cleanPath: String
        if path == "/" || path.isEmpty {
            cleanPath = "index.html"
        } else {
            cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        }

        // Try exact relative path match
        if let fileURL = fileMap[cleanPath.lowercased()],
           let data = try? Data(contentsOf: fileURL) {
            respond(task: task, url: task.request.url!, data: data,
                    mimeType: mimeType(for: fileURL.pathExtension.lowercased()))
            return
        }

        // Try filename-only match as fallback
        let filename = (cleanPath as NSString).lastPathComponent.lowercased()
        if let fileURL = fileMap[filename],
           let data = try? Data(contentsOf: fileURL) {
            respond(task: task, url: task.request.url!, data: data,
                    mimeType: mimeType(for: fileURL.pathExtension.lowercased()))
            return
        }

        // SPA fallback: serve index.html for unmatched routes
        if let indexURL = fileMap["index.html"],
           let indexData = try? Data(contentsOf: indexURL) {
            respond(task: task, url: task.request.url!, data: indexData, mimeType: "text/html")
        } else {
            failTask(task, code: 404, message: "File not found: \(cleanPath)")
        }
    }

    // MARK: - Response Helpers

    private func respond(task: WKURLSchemeTask, url: URL, data: Data, mimeType: String) {
        guard isTaskActive(task) else { return }

        // FIX: Use HTTPURLResponse instead of URLResponse for proper status codes and headers.
        // This ensures the web view correctly interprets CORS and content-type.
        let headers: [String: String] = [
            "Content-Type": mimeType,
            "Content-Length": "\(data.count)",
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "no-cache"
        ]

        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!

        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
        untrackTask(task)
    }

    private func failTask(_ task: WKURLSchemeTask, code: Int, message: String) {
        guard isTaskActive(task) else { return }
        print("[DumpsterScheme] Error \(code): \(message)")
        task.didFailWithError(NSError(
            domain: "DumpsterSchemeHandler",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        ))
        untrackTask(task)
    }

    // MARK: - MIME Types

    private func mimeType(for ext: String) -> String {
        switch ext {
        case "html":        return "text/html; charset=utf-8"
        case "js", "mjs":   return "application/javascript; charset=utf-8"
        case "css":         return "text/css; charset=utf-8"
        case "json":        return "application/json; charset=utf-8"
        case "png":         return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif":         return "image/gif"
        case "svg":         return "image/svg+xml"
        case "webp":        return "image/webp"
        case "ico":         return "image/x-icon"
        case "woff2":       return "font/woff2"
        case "woff":        return "font/woff"
        case "ttf":         return "font/ttf"
        case "otf":         return "font/otf"
        case "mp4":         return "video/mp4"
        case "webm":        return "video/webm"
        case "mp3":         return "audio/mpeg"
        case "wav":         return "audio/wav"
        case "xml":         return "application/xml"
        case "txt":         return "text/plain; charset=utf-8"
        case "map":         return "application/json"
        default:            return "application/octet-stream"
        }
    }
}
