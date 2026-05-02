import Foundation

// MARK: - Caption Service (Backward Compatibility Bridge)

/// This file provides backward compatibility with code that still references CaptionService.
/// All functionality has been migrated to LLMService, which supports multiple AI providers.
/// CaptionService now acts as a thin wrapper that delegates to LLMService.

final class CaptionService: ObservableObject {

    // MARK: - Singleton

    static let shared = CaptionService()

    // MARK: - Published State (Delegates to LLMService)

    var isGenerating: Bool { LLMService.shared.isGenerating }
    var lastError: String? { LLMService.shared.lastError }

    // MARK: - API Configuration (Delegates to LLMService)

    var apiKey: String {
        get { LLMService.shared.apiKey(for: .openai) }
        set { LLMService.shared.setAPIKey(newValue, for: .openai) }
    }

    static var defaultAPIKey: String = ""

    var hasAPIKey: Bool { LLMService.shared.hasAnyAPIKey }

    // MARK: - Type Aliases for Backward Compatibility

    typealias CaptionResult = LLMService.CaptionResult
    typealias CaptionRequest = LLMService.CaptionRequest

    // MARK: - Caption Generation (Delegates to LLMService)

    func generateCaptions(for request: CaptionRequest) async throws -> CaptionResult {
        try await LLMService.shared.generateCaptions(for: request)
    }

    func generateCaptions(for requests: [CaptionRequest]) async throws -> [CaptionResult] {
        try await LLMService.shared.generateCaptions(for: requests)
    }

    // MARK: - Fallback Captions

    static func fallbackCaptions(for category: String, title: String) -> CaptionResult {
        LLMService.fallbackCaptions(for: category, title: title)
    }

    // MARK: - Errors (Backward Compatibility)

    enum CaptionError: LocalizedError {
        case noAPIKey
        case encodingFailed
        case invalidResponse
        case parseFailed
        case apiError(statusCode: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "No API key configured. Add one in the File Cabinet menu."
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
