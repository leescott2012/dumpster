import Foundation

// MARK: - Caption Service (OpenAI Integration)

/// Generates contextual captions for photo dumps using the OpenAI Chat Completions API.
/// The service takes photo labels, categories, and cluster metadata to produce
/// captions that match the vibe of each dump.

final class CaptionService: ObservableObject {

    // MARK: - Singleton

    static let shared = CaptionService()

    // MARK: - Published State

    @Published var isGenerating = false
    @Published var lastError: String?

    // MARK: - API Configuration

    /// API key storage — for development, reads from UserDefaults or falls back to a
    /// compile-time constant. For production, migrate to Keychain.
    var apiKey: String {
        get {
            if let stored = UserDefaults.standard.string(forKey: "openai_api_key"), !stored.isEmpty {
                return stored
            }
            // Fallback: compile-time constant (replace for local testing)
            return CaptionService.defaultAPIKey
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "openai_api_key")
        }
    }

    /// Set this at build time or via Settings for local testing.
    /// In production, use Keychain or a server-side proxy instead.
    static var defaultAPIKey: String = ""

    var hasAPIKey: Bool { !apiKey.isEmpty }

    // MARK: - Models

    struct CaptionResult: Identifiable, Codable {
        let id: String
        let dumpTitle: String
        let captions: [String]
        let vibe: String

        init(dumpTitle: String, captions: [String], vibe: String) {
            self.id = UUID().uuidString
            self.dumpTitle = dumpTitle
            self.captions = captions
            self.vibe = vibe
        }
    }

    struct CaptionRequest {
        let dumpTitle: String
        let category: String
        let labels: [String]
        let photoCount: Int
    }

    // MARK: - Caption Generation

    /// Generate captions for a single dump cluster.
    func generateCaptions(for request: CaptionRequest) async throws -> CaptionResult {
        guard hasAPIKey else {
            throw CaptionError.noAPIKey
        }

        // ── Credit gate ──
        let credits = await CreditManager.shared
        guard await credits.canAfford(.generateCaptions) else {
            throw CaptionError.insufficientCredits
        }

        await MainActor.run { isGenerating = true; lastError = nil }
        defer { Task { @MainActor in isGenerating = false } }

        let systemPrompt = """
        You are a creative social media caption writer for a photo dump app called DUMPSTER. \
        Photo dumps are curated collections of photos shared as a carousel on Instagram or similar platforms. \
        Write captions that are short, punchy, and match the vibe of the photos. \
        Use lowercase aesthetic when appropriate. Mix in relevant emoji sparingly. \
        Never use hashtags. Keep each caption under 150 characters.
        """

        let uniqueLabels = Array(Set(request.labels)).prefix(20).joined(separator: ", ")
        let userPrompt = """
        Generate 5 caption options for a photo dump titled "\(request.dumpTitle)".
        Category: \(request.category)
        Photo vibes/labels: \(uniqueLabels)
        Number of photos: \(request.photoCount)

        Also provide a one-word "vibe" descriptor (like "moody", "luxe", "golden", "raw", "dreamy").

        Respond ONLY with valid JSON in this exact format:
        {"captions": ["caption1", "caption2", "caption3", "caption4", "caption5"], "vibe": "descriptor"}
        """

        let body: [String: Any] = [
            "model": "gpt-4.1-nano",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.9,
            "max_tokens": 300
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            throw CaptionError.encodingFailed
        }

        var urlRequest = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = jsonData
        urlRequest.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CaptionError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            let message = "API returned \(httpResponse.statusCode): \(errorBody)"
            await MainActor.run { lastError = message }
            throw CaptionError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        // Parse the OpenAI response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw CaptionError.parseFailed
        }

        // Extract JSON from the content (handle markdown code fences)
        let cleanContent = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let contentData = cleanContent.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any],
              let captions = parsed["captions"] as? [String] else {
            // Fallback: return the raw content as a single caption
            return CaptionResult(
                dumpTitle: request.dumpTitle,
                captions: [content.trimmingCharacters(in: .whitespacesAndNewlines)],
                vibe: "creative"
            )
        }

        let vibe = (parsed["vibe"] as? String) ?? "curated"

        // ── Deduct credit on success ──
        await CreditManager.shared.spend(.generateCaptions)

        return CaptionResult(
            dumpTitle: request.dumpTitle,
            captions: captions,
            vibe: vibe
        )
    }

    /// Generate captions for multiple dump clusters in parallel.
    func generateCaptions(for requests: [CaptionRequest]) async throws -> [CaptionResult] {
        try await withThrowingTaskGroup(of: CaptionResult.self) { group in
            for request in requests {
                group.addTask {
                    try await self.generateCaptions(for: request)
                }
            }
            var results: [CaptionResult] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }
    }

    // MARK: - Fallback Captions (No API Key)

    /// Returns locally-generated fallback captions when no API key is available.
    static func fallbackCaptions(for category: String, title: String) -> CaptionResult {
        let captionPool: [String: [String]] = [
            "AUTOMOTIVE": [
                "the whips don't miss",
                "horsepower therapy",
                "parked and posted",
                "vroom with a view",
                "keys to the good life"
            ],
            "PORTRAIT": [
                "main character energy",
                "no caption needed",
                "face card never declines",
                "the crew assembled",
                "we don't take bad photos"
            ],
            "NIGHTLIFE": [
                "after dark hits different",
                "the night is still young",
                "neon state of mind",
                "last night was a movie",
                "dark mode activated"
            ],
            "DINING": [
                "ate and left no crumbs",
                "the table is set",
                "fork yeah",
                "good food good mood",
                "culinary cinema"
            ],
            "TRAVEL": [
                "somewhere between here and paradise",
                "wanderlust dump",
                "out of office forever",
                "new places same me",
                "the world is the vibe"
            ],
            "FASHION": [
                "the fits don't miss",
                "drip check passed",
                "styled not styled",
                "closet chronicles",
                "outfit of the era"
            ],
            "FITNESS": [
                "grind don't stop",
                "built not bought",
                "sweat equity",
                "the work speaks",
                "iron therapy"
            ],
            "ART": [
                "art is the answer",
                "gallery hours",
                "curated chaos",
                "visual therapy",
                "the culture dump"
            ],
            "STUDIO": [
                "in the lab",
                "studio magic",
                "sounds and scenes",
                "behind the boards",
                "creating something"
            ]
        ]

        let captions = captionPool[category] ?? [
            "photo dump loading...",
            "a curated mess",
            "no context needed",
            "the dump speaks for itself",
            "vibes only"
        ]

        return CaptionResult(
            dumpTitle: title,
            captions: captions,
            vibe: "curated"
        )
    }

    // MARK: - Errors

    enum CaptionError: LocalizedError {
        case noAPIKey
        case insufficientCredits
        case encodingFailed
        case invalidResponse
        case parseFailed
        case apiError(statusCode: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .insufficientCredits:
                return "Not enough credits. Purchase more to continue."
            case .noAPIKey:
                return "No OpenAI API key configured. Add one in Settings."
            case .encodingFailed:
                return "Failed to encode the request."
            case .invalidResponse:
                return "Received an invalid response from the API."
            case .parseFailed:
                return "Failed to parse the caption response."
            case .apiError(let code, let msg):
                return "API error (\(code)): \(msg)"
            }
        }
    }
}
