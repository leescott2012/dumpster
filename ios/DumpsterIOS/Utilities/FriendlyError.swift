import Foundation

/// Maps a raw error to a short, user-facing message and logs the full detail
/// via CrashReporter for debugging — never show `error.localizedDescription`
/// straight to the user. Mirrors the web app's `friendlyError()`
/// (dumpster-web/client/src/lib/friendlyError.ts): callers there set the
/// mapped text as the visible UI state instead of the raw error; this is the
/// native equivalent single choke-point.
///
/// ponytail: LLMError/CaptionError already carry curated, short copy via
/// LocalizedError for their common cases (noAPIKey, insufficientCredits,
/// encodingFailed, etc.) — this only adds a layer for the cases that still
/// leak raw provider/network text (apiError with an uncommon status code,
/// URLError, and anything else).
enum FriendlyError {
    static func message(for error: Error, tags: [String: String] = [:]) -> String {
        CrashReporter.shared.capture(error, tags: tags)

        if let urlError = error as? URLError {
            return urlError.code == .timedOut
                ? "That took too long. Try again."
                : "Can't reach the server. Check your connection and try again."
        }

        let raw = error.localizedDescription
        let lower = raw.lowercased()
        if lower.contains("overloaded") {
            return "The AI provider is overloaded right now. Try again in a minute."
        }
        if lower.contains("rate_limit") || lower.contains("429") || lower.contains("too many requests") {
            return "Too many AI requests right now. Wait a moment and try again."
        }

        if let llmError = error as? LLMService.LLMError,
           case .apiError(let code, _) = llmError, !(400...403).contains(code) {
            return "The AI provider had a problem (error \(code)). Try again."
        }
        if error is LLMService.LLMError || error is CaptionService.CaptionError {
            return raw
        }

        return "Something went wrong. Try again."
    }
}
