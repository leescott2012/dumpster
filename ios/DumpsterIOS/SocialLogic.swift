import Foundation

// Pure notification/messaging rules. Mirrors web shared/notifications.ts (copy must match).
// Check: swiftc -parse-as-library ios/DumpsterIOS/SocialLogic.swift ios/scripts/social.check.swift -o /tmp/sc && /tmp/sc

enum SocialLogic {
    static let dmMaxLen = 2000

    /// YYYY-MM-DD in the user's LOCAL calendar (server dedupes the daily reminder on it).
    static func localDay(_ d: Date = Date(), calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func dmTitle(_ name: String, _ count: Int) -> String {
        count <= 1 ? "New message from \(name)" : "\(count) new messages from \(name)"
    }

    /// Next count for a rolling row: keep counting while unread, restart at 1 once it was read.
    static func nextRollingCount(readAt: String?, count: Int?, exists: Bool) -> Int {
        if !exists || readAt != nil { return 1 }
        return max(1, count ?? 1) + 1
    }

    static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        // "2026-01-02T03:04:05.123456+00:00" variants: drop the fraction and retry.
        let trimmed = s.replacingOccurrences(of: "\\.\\d+", with: "", options: .regularExpression)
        return f.date(from: trimmed)
    }

    /// Newest-first items under Today / Yesterday / date headings (local time of `now`).
    static func groupByDay<T>(_ items: [T], now: Date, calendar: Calendar = .current,
                              date: (T) -> Date) -> [(label: String, items: [T])] {
        var out: [(label: String, items: [T])] = []
        let today = calendar.startOfDay(for: now)
        for it in items {
            let d = date(it)
            let diff = calendar.dateComponents([.day], from: calendar.startOfDay(for: d), to: today).day ?? 0
            let label: String
            if diff <= 0 { label = "Today" }
            else if diff == 1 { label = "Yesterday" }
            else {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US")
                f.calendar = calendar
                f.timeZone = calendar.timeZone
                f.dateFormat = calendar.component(.year, from: d) == calendar.component(.year, from: now) ? "MMM d" : "MMM d, yyyy"
                label = f.string(from: d)
            }
            if let last = out.last, last.label == label { out[out.count - 1].items.append(it) }
            else { out.append((label, [it])) }
        }
        return out
    }

    enum NavTarget: Equatable { case connections, dm(String), taste, credits }

    /// Notification links -> in-app targets (same link strings the server writes).
    static func parseLink(_ link: String?) -> NavTarget? {
        guard let link else { return nil }
        if link.hasPrefix("/messages/") {
            let id = String(link.dropFirst("/messages/".count))
            if id.count == 36, id.allSatisfy({ $0.isHexDigit || $0 == "-" }) { return .dm(id) }
            return nil
        }
        switch link {
        case "/connections": return .connections
        case "/taste": return .taste
        case "/credits": return .credits
        default: return nil
        }
    }

    static func timeAgo(_ d: Date, now: Date = Date()) -> String {
        let min = Int(now.timeIntervalSince(d) / 60)
        if min < 1 { return "just now" }
        if min < 60 { return "\(min)m" }
        let hr = min / 60
        return hr < 24 ? "\(hr)h" : "\(hr / 24)d"
    }

    static func badgeText(_ n: Int) -> String { n > 9 ? "9+" : "\(n)" }
}
