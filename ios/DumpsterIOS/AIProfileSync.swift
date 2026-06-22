import Foundation
import SwiftData

// MARK: - AI Profile Sync (NATIVE_PORT.md §1)
//
// Native port of client/src/lib/aiProfileSync.ts.
// Keeps taste_profile, ai_rules, and caption_pool in sync with Supabase
// so the user's AI knowledge persists across iOS devices (and web).
//
// What syncs:    taste_profile, ai_rules, caption_pool
// What does NOT: photos, dumps, workspace state
//
// Merge semantics (must match web exactly):
// - Scalars (taste_profile, ai_rules): cloud wins if non-empty, else keep local.
// - Caption pool: union by id. Tombstone (deleted=true) from either side wins.
// - Second-pass dedup by (style|text) lowercase — resolves legacy random-id duplicates.
//   Conflict priority: tombstone > favorited/banned flag > older createdAt.
//
// UserDefaults keys:
//   "ai_style_profile" = taste_profile
//   "ai_rules"         = ai_rules
//   DumpCaption SwiftData rows with dumpId == nil = caption_pool

// MARK: - Cloud shape

private struct CloudCaption: Codable {
    var id: String
    var text: String
    var style: String
    var favorited: Bool
    var banned: Bool
    var deleted: Bool?
    var createdAt: Double       // Unix ms (matches web)
    var dumpId: String?
}

private struct CloudAIProfile: Codable {
    var taste_profile: String
    var ai_rules: String
    var caption_pool: [CloudCaption]
    var updated_at: String
}

// MARK: - Sync service

@MainActor
final class AIProfileSync {

    // MARK: - Singleton
    static let shared = AIProfileSync()
    private init() {}

    // MARK: - Debounce state
    private var saveTask: Task<Void, Never>?

    // MARK: - One-shot sync on sign-in

    /// Mirror of syncAIProfileOnSignIn(userId) in aiProfileSync.ts.
    ///
    /// Pass a ModelContext that can query / insert / delete DumpCaption rows.
    /// If context is nil (e.g., called before SwiftData is ready) the sync is skipped.
    func syncOnSignIn(userId: String, jwt: String, context: ModelContext? = nil) async {
        let ctx = context ?? ModelContextHolder.shared.context
        guard let ctx else {
            print("[AIProfileSync] no model context — skipping sync")
            return
        }

        let cloud: CloudAIProfile?
        do {
            cloud = try await loadCloud(userId: userId, jwt: jwt)
        } catch SupabaseClient.SupabaseError.noRow {
            // New user — bootstrap from local
            try? await saveCloud(userId: userId, jwt: jwt, context: ctx)
            return
        } catch {
            // Transient error — leave cloud alone, don't overwrite
            print("[AIProfileSync] cloud load failed — skipping sync:", error.localizedDescription)
            CrashReporter.shared.capture(error, tags: ["action": "ai_profile_sync_sign_in"])
            return
        }

        guard let cloud else {
            try? await saveCloud(userId: userId, jwt: jwt, context: ctx)
            return
        }

        mergeIntoLocal(cloud: cloud, context: ctx)
        // Push merged state back so cloud reflects the union
        Task {
            try? await saveCloud(userId: userId, jwt: jwt, context: ctx)
        }
    }

    // MARK: - Debounced save

    /// Call after any mutation to taste_profile, ai_rules, or caption pool.
    /// 2s debounce matching the web implementation.
    func scheduleSave(userId: String, jwt: String, context: ModelContext? = nil) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            let ctx = context ?? ModelContextHolder.shared.context
            guard let ctx else { return }
            try? await saveCloud(userId: userId, jwt: jwt, context: ctx)
        }
    }

    // MARK: - Load from Supabase

    private func loadCloud(userId: String, jwt: String) async throws -> CloudAIProfile? {
        let query = "user_id=eq.\(userId)&select=taste_profile,ai_rules,caption_pool,updated_at"
        let data = try await SupabaseClient.shared.get(table: "user_ai_profile", query: query, jwt: jwt)
        guard let profile = try? JSONDecoder().decode(CloudAIProfile.self, from: data) else {
            return nil
        }
        return profile
    }

    // MARK: - Save to Supabase

    func saveCloud(userId: String, jwt: String, context: ModelContext) async throws {
        let taste = UserDefaults.standard.string(forKey: "ai_style_profile") ?? ""
        let rules = UserDefaults.standard.string(forKey: "ai_rules") ?? ""
        let rawCaptions = fetchRawCaptions(context: context)   // includes tombstones

        let cloudCaptions = rawCaptions.map { c -> [String: Any] in
            var d: [String: Any] = [
                "id": c.id,
                "text": c.text,
                "style": c.style,
                "favorited": c.favorited,
                "banned": c.banned,
                "deleted": c.deleted,
                "createdAt": c.createdAt.timeIntervalSince1970 * 1000,
            ]
            if let dumpId = c.dumpId { d["dumpId"] = dumpId }
            return d
        }

        let body: [String: Any] = [
            "user_id": userId,
            "taste_profile": taste,
            "ai_rules": rules,
            "caption_pool": cloudCaptions,
            "updated_at": ISO8601DateFormatter().string(from: Date()),
        ]

        try await SupabaseClient.shared.upsert(table: "user_ai_profile", body: body, jwt: jwt)
    }

    // MARK: - Merge cloud → local

    /// Exact port of mergeIntoLocal() in aiProfileSync.ts.
    private func mergeIntoLocal(cloud: CloudAIProfile, context: ModelContext) {

        // — Scalars ——————————————————————————————————————————————————————
        let localTaste = UserDefaults.standard.string(forKey: "ai_style_profile") ?? ""
        if !cloud.taste_profile.isEmpty && localTaste.isEmpty {
            UserDefaults.standard.set(cloud.taste_profile, forKey: "ai_style_profile")
        } else if !cloud.taste_profile.isEmpty && !localTaste.isEmpty && cloud.taste_profile != localTaste {
            let localLines = Set(localTaste.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
            let newLines = cloud.taste_profile
                .components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !localLines.contains($0.trimmingCharacters(in: .whitespaces)) }
            if !newLines.isEmpty {
                UserDefaults.standard.set(localTaste + "\n" + newLines.joined(separator: "\n"),
                                          forKey: "ai_style_profile")
            }
        }

        let localRules = UserDefaults.standard.string(forKey: "ai_rules") ?? ""
        if !cloud.ai_rules.isEmpty && localRules.isEmpty {
            UserDefaults.standard.set(cloud.ai_rules, forKey: "ai_rules")
        }
        // If both have rules, prefer local (user typed those explicitly, don't override).

        // — Caption pool ——————————————————————————————————————————————————
        let localRaw = fetchRawCaptions(context: context)
        var localById: [String: DumpCaption] = [:]
        for c in localRaw { localById[c.id] = c }

        var cloudById: [String: CloudCaption] = [:]
        for c in cloud.caption_pool { cloudById[c.id] = c }

        // Union by id with tombstone-aware merge
        var merged: [(DumpCaption?, CloudCaption?)] = []
        for (id, cloudCap) in cloudById {
            merged.append((localById[id], cloudCap))
        }
        for (id, localCap) in localById {
            if cloudById[id] == nil {
                merged.append((localCap, nil))
            }
        }

        // Apply merge rules
        for (local, cloud) in merged {
            let cloudDeleted = cloud?.deleted ?? false
            let localDeleted = local?.deleted ?? false
            let tombstone = cloudDeleted || localDeleted

            if let local {
                // Update existing local row
                if tombstone {
                    local.deleted = true
                    local.favorited = false
                    local.banned = false
                } else if let cloud {
                    // Cloud's flag state wins for favorited/banned
                    local.favorited = cloud.favorited
                    local.banned = cloud.banned
                }
            } else if let cloud, local == nil {
                // New caption from cloud — insert into SwiftData
                let cap = DumpCaption(
                    id: cloud.id,
                    text: cloud.text,
                    style: cloud.style,
                    dumpId: cloud.dumpId,
                    favorited: tombstone ? false : cloud.favorited,
                    banned: tombstone ? false : cloud.banned,
                    deleted: tombstone
                )
                cap.createdAt = Date(timeIntervalSince1970: cloud.createdAt / 1000)
                context.insert(cap)
            }
        }

        // — Second-pass dedup by (style|text) ————————————————————————————
        // Handles legacy rows where the same seed caption ended up with different
        // random IDs across devices. Without this, every new device adds seed duplicates.
        //
        // Conflict priority (highest wins):
        //   1. Tombstoned rows — keep the deletion
        //   2. Rows with favorited or banned flag — preserve user state
        //   3. Older createdAt — the original, not the duplicate

        func rank(_ c: DumpCaption) -> Int {
            if c.deleted { return 3 }
            if c.favorited || c.banned { return 2 }
            return 1
        }

        let allAfterMerge = fetchRawCaptions(context: context)
        var seen: [String: DumpCaption] = [:]

        let sorted = allAfterMerge.sorted {
            let ra = rank($0), rb = rank($1)
            if ra != rb { return ra > rb }
            return $0.createdAt < $1.createdAt
        }

        for cap in sorted {
            let key = cap.style + "|" + cap.text.trimmingCharacters(in: .whitespaces).lowercased()
            if let existing = seen[key] {
                // Duplicate — delete the lower-priority one (the current `cap`, since sorted higher-first)
                // Actually: `seen` already has the winner, so we delete the current one
                context.delete(cap)
                _ = existing // silence warning
            } else {
                seen[key] = cap
            }
        }

        try? context.save()
    }

    // MARK: - SwiftData helpers

    /// All pool-level captions including tombstones. Mirror of loadCaptionsRaw() on web.
    func fetchRawCaptions(context: ModelContext) -> [DumpCaption] {
        let descriptor = FetchDescriptor<DumpCaption>(
            predicate: #Predicate { $0.dumpId == nil }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Visible pool captions — tombstones excluded. Mirror of loadCaptions() on web.
    func fetchVisibleCaptions(context: ModelContext) -> [DumpCaption] {
        let descriptor = FetchDescriptor<DumpCaption>(
            predicate: #Predicate { $0.dumpId == nil && $0.deleted == false },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Tombstone-delete a caption. Mirror of removeCaption(id) on web.
    func removeCaption(id: String, context: ModelContext) {
        let descriptor = FetchDescriptor<DumpCaption>(
            predicate: #Predicate { $0.id == id }
        )
        guard let cap = (try? context.fetch(descriptor))?.first else { return }
        cap.deleted = true
        cap.favorited = false
        cap.banned = false
        try? context.save()
    }

    // MARK: - Seed captions (first launch)

    /// Seed the pool with default captions on first install.
    /// Uses DumpCaption.seedId() so IDs are deterministic across all devices.
    func seedIfNeeded(context: ModelContext) {
        let existing = fetchRawCaptions(context: context)
        guard existing.isEmpty else { return }

        // IMPORTANT: these texts must be byte-for-byte identical to seedCaptions() in
        // web/client/src/lib/captionPool.ts so deterministic IDs match across platforms.
        let seeds: [(style: String, text: String)] = [
            ("storytelling", "the kind of night you tell stories about"),
            ("storytelling", "we didn't plan this, it just happened"),
            ("storytelling", "somewhere between the chaos and the calm"),
            ("storytelling", "a collection of moments I refuse to forget"),
            ("emoji",        "📸✨🔥"),
            ("emoji",        "🌙💫🖤"),
            ("emoji",        "🏎💨✨"),
            ("clean",        "recent."),
            ("clean",        "documented."),
            ("clean",        "filed under: good times"),
            ("numbered",     "1. showed up  2. showed out"),
            ("numbered",     "1/10 of why this week hit different"),
        ]

        let now = Date()
        for (i, s) in seeds.enumerated() {
            let cap = DumpCaption(
                id: DumpCaption.seedId(style: s.style, text: s.text),
                text: s.text,
                style: s.style
            )
            cap.createdAt = Date(timeIntervalSinceNow: -Double(seeds.count - i))
            _ = now
            context.insert(cap)
        }
        try? context.save()
    }
}

// MARK: - ModelContextHolder
//
// Holds a shared ModelContext so AIProfileSync can reach SwiftData
// without requiring callers to always pass a context.
// Set once from DumpsterApp after the modelContainer is ready.

@MainActor
final class ModelContextHolder {
    static let shared = ModelContextHolder()
    var context: ModelContext?
    private init() {}
}
