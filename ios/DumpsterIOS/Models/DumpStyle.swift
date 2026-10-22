import Foundation

/// Mirrors TASTE_PROFILE_MAX / AI_RULES_MAX / TASTE_PREF_MAX in client/src/lib/captionPool.ts.
enum AIProfileLimits {
    static let tasteProfileMax = 2000
    static let aiRulesMax = 1500
    static let tastePrefMax = 160
}

extension Notification.Name {
    static let dumpStylesChanged = Notification.Name("dumpStylesChanged")
}

/// Named, reusable dump recipe. Port of DumpStyle in client/src/lib/captionPool.ts.
/// Persisted as JSON in UserDefaults ("dump_styles") + active id ("active_dump_style"),
/// synced via AIProfileSync (user_ai_profile.dump_styles / active_dump_style).
struct DumpStyle: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var profile: String
    var rules: String
    var updatedAt: String   // ISO8601 with ms, same format as JS toISOString()

    static let stylesKey = "dump_styles"
    static let activeKey = "active_dump_style"

    static func nowISO() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }

    static func new() -> DumpStyle {
        DumpStyle(id: UUID().uuidString.lowercased(), name: "New style", profile: "", rules: "", updatedAt: nowISO())
    }

    static func load() -> [DumpStyle] {
        guard let data = UserDefaults.standard.string(forKey: stylesKey)?.data(using: .utf8),
              let list = try? JSONDecoder().decode([DumpStyle].self, from: data) else { return [] }
        return list
    }

    static func save(_ styles: [DumpStyle]) {
        guard let data = try? JSONEncoder().encode(styles), let s = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(s, forKey: stylesKey)
    }

    static func activeId() -> String { UserDefaults.standard.string(forKey: activeKey) ?? "" }

    /// "ACTIVE DUMP STYLE" section for the taste block; nil when none active.
    static func activeBlock() -> String? {
        let id = activeId()
        guard !id.isEmpty, let s = load().first(where: { $0.id == id }) else { return nil }
        let body = [s.profile, s.rules]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return "ACTIVE DUMP STYLE — \"\(s.name)\" (follow this recipe for structure, sequencing, poses, and mix):"
            + (body.isEmpty ? "" : "\n" + body)
    }

    /// Union by id; newer updatedAt wins (matches aiProfileSync.ts).
    static func merge(local: [DumpStyle], cloud: [DumpStyle]) -> [DumpStyle] {
        var order: [String] = []
        var byId: [String: DumpStyle] = [:]
        for s in local + cloud {
            if let prev = byId[s.id] {
                if s.updatedAt > prev.updatedAt { byId[s.id] = s }
            } else {
                byId[s.id] = s
                order.append(s.id)
            }
        }
        return order.compactMap { byId[$0] }
    }
}
