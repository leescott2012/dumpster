import Foundation

// MARK: - Unified Multi-Provider LLM Service

/// Routes AI requests to whichever LLM provider has a valid API key configured.
/// Supports OpenAI, Claude (Anthropic), Gemini (Google), Manus, and Perplexity.

final class LLMService: ObservableObject {

    // MARK: - Singleton

    static let shared = LLMService()

    // MARK: - Published State

    @Published var isGenerating = false
    @Published var lastError: String?
    @Published var activeProvider: LLMProvider?

    // MARK: - Provider Definitions

    enum LLMProvider: String, CaseIterable, Identifiable, Codable {
        case openai     = "OpenAI"
        case claude     = "Claude"
        case gemini     = "Gemini"
        case manus      = "Manus"
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
            case .openai:     return "gpt-4.1-mini"
            case .claude:     return "claude-opus-4-5"
            case .gemini:     return "gemini-2.5-flash"
            case .manus:      return "manus-1"
            case .perplexity: return "sonar"
            }
        }

        var availableModels: [String] {
            switch self {
            case .openai:
                return ["gpt-4.1-mini", "gpt-4.1-nano", "gpt-4.1", "gpt-4o", "gpt-4o-mini"]
            case .claude:
                return ["claude-opus-4-5", "claude-sonnet-4-5", "claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022"]
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

        var storageKey: String { "llm_api_key_\(rawValue.lowercased())" }
        var modelStorageKey: String { "llm_model_\(rawValue.lowercased())" }
    }

    // MARK: - Task Types

    enum TaskType: String {
        case caption    = "caption"
        case title      = "title"
        case label      = "label"
        case categorize = "categorize"
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
        !apiKey(for: provider).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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

    var labelingSensitivity: Double {
        get {
            let val = UserDefaults.standard.double(forKey: "llm_labeling_sensitivity")
            return val == 0 ? 0.5 : val
        }
        set { UserDefaults.standard.set(newValue, forKey: "llm_labeling_sensitivity") }
    }

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
            case .aesthetic: return "Write in a dreamy, aesthetic style. Use soft language and lowercase."
            case .minimal:   return "Write extremely short, minimal captions. One line max."
            case .witty:     return "Write clever, witty captions with wordplay."
            case .poetic:    return "Write poetic, evocative captions with imagery."
            }
        }
    }

    var captionStyle: CaptionStyle {
        get {
            let raw = UserDefaults.standard.string(forKey: "llm_caption_style") ?? CaptionStyle.casual.rawValue
            return CaptionStyle(rawValue: raw) ?? .casual
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "llm_caption_style") }
    }

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
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "llm_intelligence_level") }
    }

    // MARK: - Provider Selection

    func preferredProvider() -> LLMProvider? {
        let priority: [LLMProvider] = [.claude, .manus, .openai, .gemini, .perplexity]
        return priority.first { hasAPIKey(for: $0) }
    }

    // MARK: - Unified Generation

    func generate(request: LLMRequest, provider: LLMProvider? = nil) async throws -> String {
        let selectedProvider = provider ?? preferredProvider()
        guard let provider = selectedProvider else { throw LLMError.noAPIKey }
        guard hasAPIKey(for: provider) else { throw LLMError.noAPIKey }

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
            return try await callOpenAICompatible(endpoint: provider.apiEndpoint, apiKey: key, model: model, request: request)
        case .claude:
            return try await callClaude(apiKey: key, model: model, request: request)
        case .gemini:
            return try await callGemini(apiKey: key, model: model, request: request)
        }
    }

    // MARK: - Generate Caption for a single dump (called from DumpCardView)
    //
    // Accepts an array of DumpPhoto objects and derives the title/category from them.

    func generateCaption(for photos: [DumpPhoto]) async throws -> CaptionResult {
        let title = photos.isEmpty ? "Photo Dump" : FormulaEngine.generateDumpTitle(for: photos)
        let category = photos.first?.category ?? "LIFESTYLE"
        return try await generateCaption(for: title, category: category)
    }

    // MARK: - User Context Block (style profile + rules + taste examples)

    /// Builds the personalization block injected into every AI request.
    /// `tasteBlock` is optional and should come from `AITasteExample.promptBlock(from:)`.
    func userContextBlock(tasteBlock: String = "") -> String {
        let profile = UserDefaults.standard.string(forKey: "ai_style_profile") ?? ""
        let rules   = UserDefaults.standard.string(forKey: "ai_rules") ?? ""

        var parts: [String] = []
        if !profile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("User's aesthetic style: \(profile.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        if !rules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Rules you MUST follow:\n\(rules.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        if !tasteBlock.isEmpty {
            parts.append(tasteBlock)
        }
        guard !parts.isEmpty else { return "" }
        return "\n\n---\n" + parts.joined(separator: "\n\n")
    }

    // MARK: - Generate Caption by title + category

    func generateCaption(for dumpTitle: String, category: String, tasteBlock: String = "") async throws -> CaptionResult {
        guard hasAnyAPIKey else {
            return LLMService.fallbackCaptions(for: category, title: dumpTitle)
        }

        let context = userContextBlock(tasteBlock: tasteBlock)
        let system = "You are an AI photo dump curator. Write 3 aesthetic captions for a photo dump. Respond with JSON: {\"captions\":[\"...\",\"...\",\"...\"],\"vibe\":\"...\"}\(context)"
        let user = "Title: \(dumpTitle)\nCategory: \(category)\nStyle: \(captionStyle.rawValue)\n\(captionStyle.promptModifier)"

        let request = LLMRequest(systemPrompt: system, userPrompt: user, temperature: 0.8, maxTokens: 500)
        let response = try await generate(request: request)
        return parseCaptionResponse(response, dumpTitle: dumpTitle)
    }

    // MARK: - Generate Captions for multiple dumps (called from AISuggestView)

    func generateCaptions(for requests: [CaptionRequest], tasteBlock: String = "") async throws -> [CaptionResult] {
        guard hasAnyAPIKey else {
            return requests.map { LLMService.fallbackCaptions(for: $0.category, title: $0.dumpTitle) }
        }

        var results: [CaptionResult] = []
        for req in requests {
            let result = try await generateCaption(for: req.dumpTitle, category: req.category, tasteBlock: tasteBlock)
            results.append(result)
        }
        return results
    }

    // MARK: - OpenAI Compatible API

    private func callOpenAICompatible(endpoint: String, apiKey: String, model: String, request: LLMRequest) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": request.systemPrompt],
                ["role": "user", "content": request.userPrompt]
            ],
            "temperature": request.temperature,
            "max_tokens": request.maxTokens
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { throw LLMError.encodingFailed }

        var urlRequest = URLRequest(url: URL(string: endpoint)!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = jsonData
        urlRequest.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else { throw LLMError.invalidResponse }
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            await MainActor.run { lastError = "API \(httpResponse.statusCode): \(errorBody)" }
            throw LLMError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else { throw LLMError.parseFailed }

        return content
    }

    // MARK: - Claude (Anthropic) API

    private func callClaude(apiKey: String, model: String, request: LLMRequest) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": request.maxTokens,
            "system": request.systemPrompt,
            "messages": [["role": "user", "content": request.userPrompt]]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { throw LLMError.encodingFailed }

        var urlRequest = URLRequest(url: URL(string: LLMProvider.claude.apiEndpoint)!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = jsonData
        urlRequest.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else { throw LLMError.invalidResponse }
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            await MainActor.run { lastError = "Claude \(httpResponse.statusCode): \(errorBody)" }
            throw LLMError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentArray = json["content"] as? [[String: Any]],
              let firstContent = contentArray.first,
              let text = firstContent["text"] as? String else { throw LLMError.parseFailed }

        return text
    }

    // MARK: - Gemini (Google) API

    private func callGemini(apiKey: String, model: String, request: LLMRequest) async throws -> String {
        let endpoint = "\(LLMProvider.gemini.apiEndpoint)/models/\(model):generateContent?key=\(apiKey)"
        let body: [String: Any] = [
            "contents": [["parts": [["text": "\(request.systemPrompt)\n\n\(request.userPrompt)"]]]],
            "generationConfig": ["temperature": request.temperature, "maxOutputTokens": request.maxTokens]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { throw LLMError.encodingFailed }

        var urlRequest = URLRequest(url: URL(string: endpoint)!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = jsonData
        urlRequest.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else { throw LLMError.invalidResponse }
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            await MainActor.run { lastError = "Gemini \(httpResponse.statusCode): \(errorBody)" }
            throw LLMError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else { throw LLMError.parseFailed }

        return text
    }

    // MARK: - Response Parsing

    private func parseCaptionResponse(_ content: String, dumpTitle: String) -> CaptionResult {
        let clean = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = clean.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let captions = parsed["captions"] as? [String] else {
            return CaptionResult(dumpTitle: dumpTitle, captions: [content.trimmingCharacters(in: .whitespacesAndNewlines)], vibe: "creative")
        }

        return CaptionResult(dumpTitle: dumpTitle, captions: captions, vibe: (parsed["vibe"] as? String) ?? "curated")
    }

    // MARK: - Fallback Captions (No API Key)

    static func fallbackCaptions(for category: String, title: String) -> CaptionResult {
        let pool: [String: [String]] = [
            "AUTOMOTIVE": ["the whips don't miss", "horsepower therapy", "parked and posted", "vroom with a view", "keys to the good life"],
            "PORTRAIT":   ["main character energy", "no caption needed", "face card never declines", "the crew assembled", "we don't take bad photos"],
            "NIGHTLIFE":  ["after dark hits different", "the night is still young", "neon state of mind", "last night was a movie", "dark mode activated"],
            "DINING":     ["ate and left no crumbs", "the table is set", "fork yeah", "good food good mood", "culinary cinema"],
            "TRAVEL":     ["somewhere between here and paradise", "wanderlust dump", "out of office forever", "new places same me", "the world is the vibe"],
            "FASHION":    ["the fits don't miss", "drip check passed", "styled not styled", "closet chronicles", "outfit of the era"],
            "FITNESS":    ["grind don't stop", "built not bought", "sweat equity", "the work speaks", "iron therapy"],
            "ART":        ["art is the answer", "gallery hours", "curated chaos", "visual therapy", "the culture dump"],
            "STUDIO":     ["in the lab", "studio magic", "sounds and scenes", "behind the boards", "creating something"]
        ]

        let captions = pool[category] ?? ["photo dump loading...", "a curated mess", "no context needed", "the dump speaks for itself", "vibes only"]
        return CaptionResult(dumpTitle: title, captions: captions, vibe: "curated")
    }

    // MARK: - Backward Compatibility

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
            case .noAPIKey:                  return "No API key configured. Tap the brain icon to open AI Settings."
            case .insufficientCredits:       return "Not enough credits. Purchase more to continue."
            case .encodingFailed:            return "Failed to encode the request."
            case .invalidResponse:           return "Received an invalid response from the API."
            case .parseFailed:               return "Failed to parse the AI response."
            case .apiError(let code, let m): return "API error (\(code)): \(m)"
            case .providerUnavailable(let n):return "\(n) is not available. Check your API key."
            }
        }
    }
}
