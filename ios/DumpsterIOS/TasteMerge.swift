import Foundation

/// Pure taste-profile merge (port of web client/src/lib/tasteMerge.ts). Foundation only so it can be self-checked
/// with swiftc. A scan lives in ONE labeled block; a rebuild replaces that block and never touches the user's text.
enum TasteMerge {
    static let maxLen = 2000 // keep equal to AIProfileLimits.tasteProfileMax
    private static let blockPattern = "(?:^|\\n)--- From Instagram @[^\\n]* ---\\n[\\s\\S]*?\\n--- end ---(?:\\n|$)"

    /// The user's own text with any earlier Instagram block removed.
    static func stripIgBlock(_ text: String) -> String {
        var s = text.replacingOccurrences(of: blockPattern, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Trim at a sentence end (or word end) to fit `limit`.
    private static func cutClean(_ text: String, _ limit: Int) -> String {
        if text.count <= limit { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        let head = String(text.prefix(max(0, limit - 1)))
        var cut = -1
        for p in [". ", "! ", "? "] {
            if let r = head.range(of: p, options: .backwards) {
                cut = max(cut, head.distance(from: head.startIndex, to: r.lowerBound))
            }
        }
        if Double(cut) > Double(limit) * 0.5 { return String(head.prefix(cut + 1)) }
        var s = head.replacingOccurrences(of: "\\s+\\S*$", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "[,;:\\s]+$", with: "", options: .regularExpression)
        return s + "."
    }

    /// Returns the profile unchanged (user text only) when it leaves too little room (< 120 chars).
    static func merge(existing: String, scrubbed: String, handle: String) -> String {
        let base = stripIgBlock(existing)
        let head = "--- From Instagram @\(handle) ---\n"
        let tail = "\n--- end ---"
        let room = maxLen - base.count - (base.isEmpty ? 0 : 2) - head.count - tail.count
        if room < 120 { return base }
        return (base.isEmpty ? "" : base + "\n\n") + head + cutClean(scrubbed, room) + tail
    }
}
