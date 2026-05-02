import Foundation

// MARK: - Unified Multi-Provider LLM Service

/// Routes AI requests to whichever LLM provider has a valid API key configured.
/// Supports OpenAI, Claude (Anthropic), Gemini (Google), Manus, and Perplexity.
/// Uses async/await Swift concurrency throughout.

final class LLMService: ObservableObject {

    // MARK: - Singleton

    static let shared = LLMService()

    // MARK: - Published State

    @Published var isGenerating = false
    @Published var lastError: String?
    @Published var activeProvider: LLMProvider?

    // MARK: - Provider Definitions

    enum LLMProvider: String, CaseIterable, Identifiable, Codable {
        case openai    = "OpenAI"
        case claude    = "Claude"
        case gemini    = "Gemini"
        case manus     = "Manus"
        case perplexity = "Perplexity"

        var id: String { rawValue }

        var displayName: String { rawValue }

        var iconName: String {
            switch self {
            case .openai:     return "brain.head.profile"
            case .claude:     return "sparkle"
            case .gemini:     return "diamond"
            case .manus:      return "hand.raised"
            case .perplexity: return "magnifyingglass.circle"
            }
        }

        var defaultModel: String {
            switch self {
            case .openai:     return "gpt-4.1-nano"
            case .claude:     return "claude-sonnet-4-20250514"
            case .gemini:     return "gemini-2.5-flash"
            case .manus:      return "manus-1"
            case .perplexity: return "sonar"
            }
        }

        var availableModels: [String] {
            switch self {
            case .openai:
                return ["gpt-4.1-nano", "gpt-4.1-mini", "gpt-4.1", "gpt-4o", "gpt-4o-mini"]
            case .claude:
                return ["claude-sonnet-4-20250514", "claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022", "claude-3-haiku-20240307"]
            case .gemini:
                return ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-2.0-flash", "gemini-1.5-pro"]
            case .manus:
                return ["manus-1", "manus-lite"]
            case .perplexity:
                return ["sonar", "sonar-pro", "sonar-reasoning", "sonar-reasoning-pro"]
            }
        }

        var apiEndpoint: String {
            switch self {
            case .openai:     return "https://api.openai.com/v1/chat/completions"
            case .claude:     return "https://api.anthropic.com/v1/messages"
            case .gemini:     return "https://generativelanguage.googleapis.com/v1beta"
            case .manus:      return "https://api.manus.im/v1/chat/completions"
            case .perplexity: return "https://api.perplexity.ai/chat/completions"
            }
        }

        var keyPrefix: String {
            switch self {
            case .openai:     return "sk-"
            case .claude:     return "sk-ant-"
            case .gemini:     return "AI"
            case .manus:      return ""
            case .perplexity: return "pplx-"
            }
        }

        var keyPlaceholder: String {
            switch self {
            case .openai:     return "sk-..."
            case .claude:     return "sk-ant-..."
            case .gemini:     return "AIza..."
            case .manus:      return "manus-..."
            case .perplexity: return "pplx-..."
            }
        }

        /// UserDefaults key for storing the API key
        var storageKey: String {
            return "llm_api_key_\(rawValue.lowercased())"
        }

        /// UserDefaults key for storing the selected model
        var modelStorageKey: String {
            return "llm_model_\(rawValue.lowercased())"
        }
    }

    // MARK: - Task Types

    enum TaskType: String {
        case caption     = "caption"
        case title       = "title"
        case label       = "label"
        case categorize  = "categorize"
    }

    // MARK: - Request / Response Models

    struct LLMRequest {
        let systemPrompt: String
        let userPrompt: String
        let temperature: Double
        let maxTokens: Int
    }

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

    struct TitleResult: Codable {
        let title: String
        let subtitle: String?
    }

    struct LabelResult: Codable {
        let labels: [String]
        let category: String
        let confidence: Double
    }

    // MARK: - API Key Management

    func apiKey(for provider: LLMProvider) -> String {
        UserDefaults.standard.string(forKey: provider.storageKey) ?? ""
    }

    func setAPIKey(_ key: String, for provider: LLMProvider) {
        UserDefaults.standard.set(key, forKey: provider.storageKey)
        objectWillChange.send()
    }

    func hasAPIKey(for provider: LLMProvider) -> Bool {
        let key = apiKey(for: provider)
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Returns true if any provider has a valid API key configured.
    var hasAnyAPIKey: Bool {
        LLMProvider.allCases.contains { hasAPIKey(for: $0) }
    }

    // MARK: - Model Selection

    func selectedModel(for provider: LLMProvider) -> String {
        UserDefaults.standard.string(forKey: provider.modelStorageKey) ?? provider.defaultModel
    }

    func setSelectedModel(_ model: String, for provider: LLMProvider) {
        UserDefaults.standard.set(model, forKey: provider.modelStorageKey)
    }

    // MARK: - Settings

    /// Labeling sensitivity: 0.0 (most permissive) to 1.0 (strictest).
    /// Controls the confidence threshold for photo auto-labeling.
    var labelingSensitivity: Double {
        get {
            let val = UserDefaults.standard.double(forKey: "llm_labeling_sensitivity")
            return val == 0 ? 0.5 : val // Default to 0.5
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "llm_labeling_sensitivity")
        }
    }

    /// Caption style preference
    enum CaptionStyle: String, CaseIterable, Identifiable, Codable {
        case casual    = "Casual"
        case aesthetic = "Aesthetic"
        case minimal   = "Minimal"
        case witty     = "Witty"
        case poetic    = "Poetic"

        var id: String { rawValue }

        var promptModifier: String {
            switch self {
            case .casual:    return "Write in a casual, conversational tone. Use lowercase aesthetic."
            case .aesthetic:  return "Write in a dreamy, aesthetic style. Use soft language and lowercase."
            case .minimal:    return "Write extremely short, minimal captions. One line max."
            case .witty:      return "Write clever, witty captions with wordplay."
            case .poetic:     return "Write poetic, evocative captions with imagery."
            }
        }
    }

    var captionStyle: CaptionStyle {
        get {
            let raw = UserDefaults.standard.string(forKey: "llm_caption_style") ?? CaptionStyle.casual.rawValue
            return CaptionStyle(rawValue: raw) ?? .casual
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "llm_caption_style")
        }
    }

    /// Auto-dump intelligence level: how aggressively the AI groups photos.
    enum IntelligenceLevel: String, CaseIterable, Identifiable, Codable {
        case conservative = "Conservative"
        case balanced     = "Balanced"
        case aggressive   = "Aggressive"

        var id: String { rawValue }

        var description: String {
            switch self {
            case .conservative: return "Fewer, tighter groups"
            case .balanced:     return "Smart grouping"
            case .aggressive:   return "More creative clusters"
            }
        }
    }

    var intelligenceLevel: IntelligenceLevel {
        get {
            let raw = UserDefaults.standard.string(forKey: "llm_intelligence_level") ?? IntelligenceLevel.balanced.rawValue
            return IntelligenceLevel(rawValue: raw) ?? .balanced
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "llm_intelligence_level")
        }
    }

    // MARK: - Provider Selection

    /// Returns the first provider with a valid API key, in priority order.
    func preferredProvider() -> LLMProvider? {
        let priority: [LLMProvider] = [.openai, .claude, .gemini, .manus, .perplexity]
        return priority.first { hasAPIKey(for: $0) }
    }

    // MARK: - Unified Generation

    /// Send a request to the best available LLM provider.
    func generate(request: LLMRequest, provider: LLMProvider? = nil) async throws -> String {
        let selectedProvider = provider ?? preferredProvider()
        guard let provider = selectedProvider else {
            throw LLMError.noAPIKey
        }

        guard hasAPIKey(for: provider) else {
            throw LLMError.noAPIKey
        }

        await MainActor.run {
            isGenerating = true
            lastError = nil
            activeProvider = provider
        }
        defer {
            Task { @MainActor in
                isGenerating = false
                activeProvider = nil
            }
        }

        let key = apiKey(for: provider)
        let model = selectedModel(for: provider)

        switch provider {
        case .openai, .manus, .perplexity:
            return try await callOpenAICompatible(
                endpoint: provider.apiEndpoint,
                apiKey: key,
                model: model,
                request: request
            )
        case .claude:
            return try await callClaude(
                apiKey: key,
                model: model,
                request: request
            )
        case .gemini:
            return try await callGemini(
                apiKey: key,
                model: model,
                request: request
            )
        }
    }

    // MARK: - Caption Generation

    /// Generate captions for a single dump cluster using the best available provider.
    func generateCaptions(for request: CaptionRequest) async throws -> CaptionResult {
        // ── Credit gate ──
        guard await CreditManager.shared.canAfford(.generateCaptions) else {
            throw LLMError.insufficientCredits
        }

        let styleModifier = captionStyle.promptModifier

        let systemPrompt = """
        You are a creative social media caption writer for a photo dump app called DUMPSTER. \
        Photo dumps are curated collections of photos shared as a carousel on Instagram or similar platforms. \
        Write captions that are short, punchy, and match the vibe of the photos. \
        \(styleModifier) \
        Mix in relevant emoji sparingly. Never use hashtags. Keep each caption under 150 characters.
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

        let llmRequest = LLMRequest(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            temperature: 0.9,
            maxTokens: 400
        )

        let content = try await generate(request: llmRequest)
        let result = parseCaptionResponse(content, dumpTitle: request.dumpTitle)
        // ── Deduct credit on success ──
        await CreditManager.shared.spend(.generateCaptions)
        return result
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

    // MARK: - Title Generation

    /// Generate a creative title for a dump based on its photos.
    func generateTitle(category: String, labels: [String], photoCount: Int) async throws -> TitleResult {
        let systemPrompt = """
        You are a creative title generator for a photo dump app called DUMPSTER. \
        Generate short, catchy titles for photo collections. Keep titles under 30 characters. \
        Match the vibe and energy of the photos.
        """

        let uniqueLabels = Array(Set(labels)).prefix(15).joined(separator: ", ")
        let userPrompt = """
        Generate a creative title for a photo dump.
        Category: \(category)
        Photo vibes/labels: \(uniqueLabels)
        Number of photos: \(photoCount)

        Respond ONLY with valid JSON:
        {"title": "Your Title Here", "subtitle": "optional short subtitle"}
        """

        let llmRequest = LLMRequest(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            temperature: 0.8,
            maxTokens: 100
        )

        let content = try await generate(request: llmRequest)
        return parseTitleResponse(content)
    }

    // MARK: - Photo Labeling & Categorization

    /// Use AI to label and categorize a photo based on Vision framework labels.
    func labelPhoto(visionLabels: [String], existingCategory: String) async throws -> LabelResult {
        let sensitivityNote: String
        switch labelingSensitivity {
        case 0.0..<0.3:
            sensitivityNote = "Be very generous with labels. Include many descriptive tags."
        case 0.3..<0.7:
            sensitivityNote = "Use balanced labeling. Include relevant and descriptive tags."
        default:
            sensitivityNote = "Be very selective with labels. Only include highly confident, specific tags."
        }

        let systemPrompt = """
        You are a photo labeling AI for a photo dump app called DUMPSTER. \
        Given Vision framework labels, provide refined human-readable labels and a category. \
        \(sensitivityNote) \
        Categories: AUTOMOTIVE, PORTRAIT, NIGHTLIFE, DINING, FITNESS, TRAVEL, ARCHITECTURE, ART, FASHION, STUDIO, LIFESTYLE.
        """

        let userPrompt = """
        Vision labels: \(visionLabels.joined(separator: ", "))
        Current category: \(existingCategory)

        Provide refined labels and confirm or update the category.
        Respond ONLY with valid JSON:
        {"labels": ["label1", "label2", "label3"], "category": "CATEGORY", "confidence": 0.85}
        """

        let llmRequest = LLMRequest(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            temperature: 0.3,
            maxTokens: 200
        )

        let content = try await generate(request: llmRequest)
        return parseLabelResponse(content, fallbackCategory: existingCategory)
    }

    // MARK: - OpenAI-Compatible API (OpenAI, Manus, Perplexity)

    private func callOpenAICompatible(
        endpoint: String,
        apiKey: String,
        model: String,
        request: LLMRequest
    ) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": request.systemPrompt],
                ["role": "user", "content": request.userPrompt]
            ],
            "temperature": request.temperature,
            "max_tokens": request.maxTokens
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            throw LLMError.encodingFailed
        }

        var urlRequest = URLRequest(url: URL(string: endpoint)!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = jsonData
        urlRequest.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            await MainActor.run { lastError = "API \(httpResponse.statusCode): \(errorBody)" }
            throw LLMError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.parseFailed
        }

        return content
    }

    // MARK: - Claude (Anthropic) API

    private func callClaude(
        apiKey: String,
        model: String,
        request: LLMRequest
    ) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": request.maxTokens,
            "system": request.systemPrompt,
            "messages": [
                ["role": "user", "content": request.userPrompt]
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            throw LLMError.encodingFailed
        }

        var urlRequest = URLRequest(url: URL(string: LLMProvider.claude.apiEndpoint)!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = jsonData
        urlRequest.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            await MainActor.run { lastError = "Claude \(httpResponse.statusCode): \(errorBody)" }
            throw LLMError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        // Claude response format: { "content": [{ "type": "text", "text": "..." }] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentArray = json["content"] as? [[String: Any]],
              let firstContent = contentArray.first,
              let text = firstContent["text"] as? String else {
            throw LLMError.parseFailed
        }

        return text
    }

    // MARK: - Gemini (Google) API

    private func callGemini(
        apiKey: String,
        model: String,
        request: LLMRequest
    ) async throws -> String {
        // Gemini uses a different endpoint structure:
        // POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={key}
        let endpoint = "\(LLMProvider.gemini.apiEndpoint)/models/\(model):generateContent?key=\(apiKey)"

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": "\(request.systemPrompt)\n\n\(request.userPrompt)"]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": request.temperature,
                "maxOutputTokens": request.maxTokens
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            throw LLMError.encodingFailed
        }

        var urlRequest = URLRequest(url: URL(string: endpoint)!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = jsonData
        urlRequest.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            await MainActor.run { lastError = "Gemini \(httpResponse.statusCode): \(errorBody)" }
            throw LLMError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        // Gemini response: { "candidates": [{ "content": { "parts": [{ "text": "..." }] } }] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw LLMError.parseFailed
        }

        return text
    }

    // MARK: - Response Parsing

    private func parseCaptionResponse(_ content: String, dumpTitle: String) -> CaptionResult {
        let cleanContent = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let contentData = cleanContent.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any],
              let captions = parsed["captions"] as? [String] else {
            return CaptionResult(
                dumpTitle: dumpTitle,
                captions: [content.trimmingCharacters(in: .whitespacesAndNewlines)],
                vibe: "creative"
            )
        }

        let vibe = (parsed["vibe"] as? String) ?? "curated"
        return CaptionResult(dumpTitle: dumpTitle, captions: captions, vibe: vibe)
    }

    private func parseTitleResponse(_ content: String) -> TitleResult {
        let cleanContent = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let contentData = cleanContent.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any],
              let title = parsed["title"] as? String else {
            return TitleResult(title: content.trimmingCharacters(in: .whitespacesAndNewlines), subtitle: nil)
        }

        let subtitle = parsed["subtitle"] as? String
        return TitleResult(title: title, subtitle: subtitle)
    }

    private func parseLabelResponse(_ content: String, fallbackCategory: String) -> LabelResult {
        let cleanContent = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let contentData = cleanContent.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any],
              let labels = parsed["labels"] as? [String] else {
            return LabelResult(labels: [], category: fallbackCategory, confidence: 0.5)
        }

        let category = (parsed["category"] as? String) ?? fallbackCategory
        let confidence = (parsed["confidence"] as? Double) ?? 0.5
        return LabelResult(labels: labels, category: category, confidence: confidence)
    }

    // MARK: - Fallback Captions (No API Key)

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

    // MARK: - Backward Compatibility

    /// Provides backward compatibility with the old CaptionService interface.
    var hasAPIKey: Bool { hasAnyAPIKey }

    // MARK: - Errors

    enum LLMError: LocalizedError {
        case noAPIKey
        case insufficientCredits
        case encodingFailed
        case invalidResponse
        case parseFailed
        case apiError(statusCode: Int, message: String)
        case providerUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "No API key configured. Add one in the AI Settings tab."
            case .insufficientCredits:
                return "Not enough credits. Purchase more to continue."
            case .encodingFailed:
                return "Failed to encode the request."
            case .invalidResponse:
                return "Received an invalid response from the API."
            case .parseFailed:
                return "Failed to parse the AI response."
            case .apiError(let code, let msg):
                return "API error (\(code)): \(msg)"
            case .providerUnavailable(let name):
                return "\(name) is not available. Check your API key."
            }
        }
    }
}
