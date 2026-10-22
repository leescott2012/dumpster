import Foundation
import SwiftData

// MARK: - Per-account local data
//
// Every signed-in account gets its OWN folder on the device:
//   Application Support/Accounts/<userId>/default.store   (SwiftData: dumps, photos, captions, ...)
//   Application Support/Accounts/<userId>/defaults.plist  (parked UserDefaults: AI rules, styles, API keys, ...)
// Signed out = the "guest" folder. Nothing is ever deleted: switching accounts only changes which
// folder is open (and which account-scoped UserDefaults are live), so switching back restores everything.
//
// Not separated: the image/video FILES in Documents (they are only reachable through each account's
// own store, and names are UUIDs) and device preferences (theme, accent, haptics, referral code).

enum AccountStore {

    static let guestId = "guest"

    static let schema = Schema([
        DumpPhoto.self, PhotoDump.self, DumpCaption.self,
        AITasteExample.self, SavedScrub.self, DumpChatMessage.self, VideoItem.self
    ] as [any PersistentModel.Type])

    private static var appSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// "guest" when signed out; otherwise the (path-safe) Supabase user id.
    static func ownerId(for userId: String?) -> String {
        let safe = (userId ?? "").filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return safe.isEmpty ? guestId : safe
    }

    static func folder(for owner: String) -> URL {
        let d = appSupport.appendingPathComponent("Accounts/\(owner)", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    // MARK: Store

    /// The pre-per-account single store (Application Support/default.store) belongs to whoever owns
    /// the device on first launch of this version: MOVE it into their folder. Never deletes anything.
    static func migrateLegacyStore(to owner: String) {
        let fm = FileManager.default
        let dest = folder(for: owner)
        guard fm.fileExists(atPath: appSupport.appendingPathComponent("default.store").path),
              !fm.fileExists(atPath: dest.appendingPathComponent("default.store").path) else { return }
        // -wal/-shm first so a crash mid-way leaves the main file for the next launch to finish the move.
        for suffix in ["-wal", "-shm", ""] {
            let src = appSupport.appendingPathComponent("default.store" + suffix)
            if fm.fileExists(atPath: src.path) {
                try? fm.moveItem(at: src, to: dest.appendingPathComponent("default.store" + suffix))
            }
        }
    }

    static func makeContainer(owner: String) -> (container: ModelContainer, recovered: Bool) {
        let config = ModelConfiguration(url: folder(for: owner).appendingPathComponent("default.store"))
        do {
            return (try ModelContainer(for: schema, configurations: config), false)
        } catch {
            CrashReporter.shared.capture(error, tags: ["action": "model_container_init"])
            // Recovery: move this account's unreadable store aside (kept as .bak, not deleted) and start fresh.
            moveStoreAside(owner: owner)
            if let c = try? ModelContainer(for: schema, configurations: config) { return (c, true) }
            // Last resort: in-memory so the app still launches instead of crashing.
            guard let m = try? ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)) else {
                preconditionFailure("SwiftData schema is invalid")   // build-time bug only
            }
            return (m, true)
        }
    }

    /// Renames the account's default.store (+ -wal/-shm) to *.bak-<timestamp>. Non-destructive.
    private static func moveStoreAside(owner: String) {
        let fm = FileManager.default
        let dir = folder(for: owner)
        let stamp = Int(Date().timeIntervalSince1970)
        for suffix in ["", "-wal", "-shm"] {
            let src = dir.appendingPathComponent("default.store" + suffix)
            if fm.fileExists(atPath: src.path) {
                try? fm.moveItem(at: src, to: dir.appendingPathComponent("default.store\(suffix).bak-\(stamp)"))
            }
        }
    }

    // MARK: UserDefaults (account-scoped keys only)

    /// ACCOUNT data. Anything not listed (theme, accent, pool prefs, referral code, per-uid flags) stays device-wide.
    private static let accountKeys: Set<String> = [
        "ai_style_profile", "ai_engagement_playbook", "ai_rules", "active_scrub_id",
        "dump_styles", "active_dump_style", "scrub_history", "label_health_v1",
        "ig_handle", "dumpster_ig_handle", "ig_pending_day", "ig_pending_unsynced", "ig_handle_pushed_value",
        "custom_labels", "dumpster_onboardingDone",
        "llm_labeling_sensitivity", "llm_caption_style", "llm_intelligence_level",
    ]
    private static let accountKeyPrefixes = ["llm_api_key_", "llm_model_", "valet_rules_seen_"]
    private static let liveOwnerKey = "dumpster_defaults_owner"

    private static func isAccountKey(_ k: String) -> Bool {
        accountKeys.contains(k) || accountKeyPrefixes.contains { k.hasPrefix($0) }
    }

    /// Makes the live UserDefaults hold `owner`'s account keys: parks the previous owner's keys in their
    /// folder (defaults.plist), clears them, restores `owner`'s parked keys if any (a first-time owner gets none).
    static func activateDefaults(for owner: String) {
        let d = UserDefaults.standard
        guard let live = d.string(forKey: liveOwnerKey) else {
            d.set(owner, forKey: liveOwnerKey)   // pre-update keys belong to whoever owns the device now
            return
        }
        guard live != owner else { return }

        var snap: [String: Any] = [:]
        for (k, v) in d.dictionaryRepresentation() where isAccountKey(k) { snap[k] = v }
        let parkFile = folder(for: live).appendingPathComponent("defaults.plist")
        guard (snap as NSDictionary).write(to: parkFile, atomically: true) else { return }   // never clear unless saved
        for k in snap.keys { d.removeObject(forKey: k) }

        let mine = folder(for: owner).appendingPathComponent("defaults.plist")
        if let saved = NSDictionary(contentsOf: mine) as? [String: Any] {
            for (k, v) in saved where isAccountKey(k) { d.set(v, forKey: k) }
        }
        d.set(owner, forKey: liveOwnerKey)
    }
}

// MARK: - Account switcher
//
// Owns the open SwiftData container for the current account. AuthManager calls switchTo(userId:)
// BEFORE it publishes a new session, so everything that runs after sign-in (cloud profile merge,
// seeding) already sees the new account's context and UserDefaults. The app root observes
// `owner`/`container` and rebuilds itself — no restart needed.

@MainActor
final class AccountSwitcher: ObservableObject {
    static let shared = AccountSwitcher()

    @Published private(set) var owner: String
    @Published private(set) var container: ModelContainer
    /// True when an unreadable store was moved aside and replaced (shows the "Local data was reset" alert).
    @Published var recoveryNotice = false

    /// Opened containers are kept for the life of the process: late background work from the previous
    /// account still has a live store, and switching back never opens a second connection to one file.
    private var containers: [String: ModelContainer] = [:]

    private init() {
        let o = AccountStore.ownerId(for: AuthManager.readStoredSession()?.userId)
        AccountStore.migrateLegacyStore(to: o)
        AccountStore.activateDefaults(for: o)
        let made = AccountStore.makeContainer(owner: o)
        owner = o
        container = made.container
        containers[o] = made.container
        recoveryNotice = made.recovered
        ModelContextHolder.shared.context = made.container.mainContext
    }

    func switchTo(userId: String?) {
        let new = AccountStore.ownerId(for: userId)
        guard new != owner else { return }
        try? container.mainContext.save()
        AIProfileSync.shared.cancelPendingSave()   // a queued upload must not read the next account's data
        SocialStore.shared.stopPolling()
        AccountStore.activateDefaults(for: new)
        LabelHealthManager.shared.reloadForAccountChange()
        let next: ModelContainer
        if let have = containers[new] {
            next = have
        } else {
            let made = AccountStore.makeContainer(owner: new)
            next = made.container
            containers[new] = next
            if made.recovered { recoveryNotice = true }
        }
        ModelContextHolder.shared.context = next.mainContext
        container = next
        owner = new
    }
}
