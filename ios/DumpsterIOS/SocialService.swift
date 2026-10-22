import Foundation
import SwiftUI
import CryptoKit

// MARK: - Social (notifications bell + messages)
//
// Talks to the same web API the web app uses (/api/notifications, /api/dm, /api/connections)
// with the user's JWT. Polling only (no realtime), same as web. Behaviour and copy mirror
// web NotificationBell / DMSheet / ConnectionsPanel.

struct AppNotification: Identifiable, Equatable {
    let id: String
    let type: String
    let title: String
    let body: String?
    let link: String?
    var readAt: String?
    let createdAt: Date
    var isRead: Bool { readAt != nil }

    init?(json: [String: Any]) {
        guard let id = json["id"] as? String, let title = json["title"] as? String else { return nil }
        self.id = id
        self.title = title
        type = json["type"] as? String ?? "system"
        body = json["body"] as? String
        link = json["link"] as? String
        readAt = json["read_at"] as? String
        createdAt = (json["created_at"] as? String).flatMap(SocialLogic.parseDate) ?? Date()
    }

    /// SF Symbol per type (web TYPE_ICON).
    var symbol: String {
        switch type {
        case "dm": return "bubble.left"
        case "connection_request": return "person.badge.plus"
        case "connection_accepted": return "person.crop.circle.badge.checkmark"
        case "bug_reply": return "ladybug"
        case "dump_comment", "comment_reply": return "text.bubble"
        case "referral_reward": return "gift"
        case "credits_low": return "bitcoinsign.circle"
        case "reminder": return "clock"
        case "admin_broadcast": return "megaphone"
        default: return "bell"
        }
    }
}

struct SocialProfile: Hashable, Identifiable {
    let id: String
    let username: String?
    var avatarColor: String? = nil
    var handle: String { "@" + (username ?? "someone") }
}

struct Conversation: Identifiable {
    let other: SocialProfile
    let lastBody: String
    let lastAt: Date
    let mine: Bool
    let unread: Int
    var id: String { other.id }
}

struct DMMessage: Identifiable, Equatable {
    let id: String
    let senderId: String
    let body: String
}

struct FriendRow: Identifiable {
    let connectionId: String
    let other: SocialProfile
    let status: String        // pending | accepted | declined
    let incoming: Bool        // I am the addressee
    var id: String { connectionId }
}

struct SocialError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
final class SocialStore: ObservableObject {
    static let shared = SocialStore()

    @Published var notifications: [AppNotification] = []
    @Published var unreadCount = 0
    @Published var dmUnread = 0
    @Published var conversations: [Conversation] = []
    @Published var friends: [FriendRow] = []
    /// Set by a notification tap / the bell; the root view opens Friends (and a thread) and clears it.
    @Published var openFriends = false
    @Published var openThreadWith: String?
    @Published var openTasteProfile = false
    @Published var openCredits = false

    private var pollTask: Task<Void, Never>?

    private let baseURL: URL = {
        if let o = Bundle.main.object(forInfoDictionaryKey: "DumpsterAPIBaseURL") as? String, let u = URL(string: o) { return u }
        return URL(string: "https://dumpster-web-manus.vercel.app")!
    }()

    // MARK: Request plumbing (same JWT pattern as ServerAI.post)

    private func call(_ method: String, _ path: String, query: [String: String] = [:], body: [String: Any]? = nil) async throws -> [String: Any] {
        guard let jwt = await AuthManager.shared.jwt else { throw SocialError(message: "Sign in required.") }
        var comps = URLComponents(url: baseURL.appendingPathComponent("api/" + path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            if code == 429 { throw SocialError(message: "Slow down a little, then try again.") }
            throw SocialError(message: json["error"] as? String ?? "Server error")
        }
        return json
    }

    // MARK: Polling (~15s, only while signed in)

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            await self?.tick()
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel(); pollTask = nil
        notifications = []; unreadCount = 0; dmUnread = 0; conversations = []; friends = []
    }

    /// "App open" tick: server creates today's reminders (Instagram, credits low) once per day.
    func tick() async {
        await pushPendingIgState()
        _ = try? await call("POST", "notifications", body: ["day": SocialLogic.localDay()])
    }

    func refresh() async {
        guard await AuthManager.shared.jwt != nil else { return }
        if let j = try? await call("GET", "notifications") {
            notifications = (j["notifications"] as? [[String: Any]] ?? []).compactMap(AppNotification.init(json:))
            unreadCount = (j["unreadCount"] as? Int) ?? notifications.filter { !$0.isRead }.count
        }
        if let j = try? await call("GET", "dm") { applyConversations(j) }
    }

    private func applyConversations(_ j: [String: Any]) {
        dmUnread = j["unreadTotal"] as? Int ?? 0
        conversations = (j["conversations"] as? [[String: Any]] ?? []).compactMap { c in
            guard let o = c["other"] as? [String: Any], let oid = o["id"] as? String,
                  let last = c["last"] as? [String: Any] else { return nil }
            return Conversation(
                other: SocialProfile(id: oid, username: o["username"] as? String),
                lastBody: last["body"] as? String ?? "",
                lastAt: (last["created_at"] as? String).flatMap(SocialLogic.parseDate) ?? Date(),
                mine: last["mine"] as? Bool ?? false,
                unread: c["unread"] as? Int ?? 0)
        }
    }

    // MARK: Bell actions

    func markAllRead() async {
        let now = ISO8601DateFormatter().string(from: Date())
        notifications = notifications.map { var n = $0; if n.readAt == nil { n.readAt = now }; return n }
        unreadCount = 0
        _ = try? await call("PATCH", "notifications", body: ["markAllRead": true])
    }

    /// Tap = mark read + open the screen it is about.
    func open(_ n: AppNotification) async {
        if !n.isRead {
            if let i = notifications.firstIndex(where: { $0.id == n.id }) {
                notifications[i].readAt = ISO8601DateFormatter().string(from: Date())
            }
            unreadCount = max(0, unreadCount - 1)
            _ = try? await call("PATCH", "notifications", body: ["id": n.id])
        }
        switch SocialLogic.parseLink(n.link) {
        case .connections: openFriends = true
        case .dm(let id): openThreadWith = id; openFriends = true
        case .taste: openTasteProfile = true
        case .credits: openCredits = true
        case nil: break
        }
    }

    // MARK: Friends

    func loadFriends() async {
        guard let j = try? await call("GET", "connections", query: ["mode": "list"]) else { return }
        friends = (j["connections"] as? [[String: Any]] ?? []).compactMap { r in
            guard let id = r["id"] as? String, let status = r["status"] as? String,
                  let o = r["other"] as? [String: Any], let oid = o["id"] as? String else { return nil }
            return FriendRow(connectionId: id, other: SocialProfile(id: oid, username: o["username"] as? String, avatarColor: o["avatar_color"] as? String),
                             status: status, incoming: r["addressee_id"] as? String != oid)
        }
    }

    // MARK: Dump visibility (PATCH /api/dump-visibility { dumpId, public }) — same route as web setDumpPublic

    /// Mirror of server normId() (api/workspace.ts): UUIDs pass through, anything else becomes the
    /// stable v5-style UUID the cloud row would carry. Must stay byte-identical to the server.
    static func cloudDumpId(_ id: String) -> String {
        if UUID(uuidString: id) != nil { return id.lowercased() }
        let h = Array(Insecure.SHA1.hash(data: Data(("dumpster:" + id).utf8)).map { String(format: "%02x", $0) }.joined())
        func s(_ a: Int, _ b: Int) -> String { String(h[a..<b]) }
        let variant = String(format: "%02x", (Int(s(16, 18), radix: 16)! & 0x3f) | 0x80)
        return s(0, 8) + "-" + s(8, 12) + "-5" + s(13, 16) + "-" + variant + s(18, 20) + "-" + s(20, 32)
    }

    /// Owner-only server-side. Throws a readable error; callers revert their optimistic flip.
    func setDumpPublic(dumpId: String, isPublic: Bool) async throws {
        do {
            _ = try await call("PATCH", "dump-visibility", body: ["dumpId": Self.cloudDumpId(dumpId), "public": isPublic])
        } catch let e as SocialError where e.message.hasPrefix("Dump not found") {
            // ponytail: iOS does not push dumps to the cloud yet (see PR), so a device-only dump has no row to flag.
            throw SocialError(message: "This dump isn't in your cloud account yet, so it can't be shared.")
        }
    }

    // MARK: Friend profile + dump comments

    struct FriendPhoto: Identifiable { let id: String; let url: URL? }
    struct FriendDump: Identifiable {
        let id: String
        let title: String
        let subtitle: String?
        let photos: [FriendPhoto]
        var commentCount: Int
    }
    struct FriendProfile { let displayName: String; var dumps: [FriendDump] }
    struct DumpComment: Identifiable {
        let id: String
        let body: String
        let mine: Bool
        let username: String?
    }

    /// GET /api/connections?mode=profile&userId= — accepted connections only (server 403 otherwise); public dumps only.
    func profile(of userId: String) async throws -> FriendProfile {
        let j = try await call("GET", "connections", query: ["mode": "profile", "userId": userId])
        let dumps = (j["dumps"] as? [[String: Any]] ?? []).compactMap { d -> FriendDump? in
            guard let id = d["id"] as? String else { return nil }
            let photos = (d["photos"] as? [[String: Any]] ?? []).compactMap { p -> FriendPhoto? in
                guard let pid = p["id"] as? String else { return nil }
                return FriendPhoto(id: pid, url: (p["url"] as? String).flatMap(URL.init(string:)))
            }
            let sub = (d["subtitle"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return FriendDump(id: id, title: d["title"] as? String ?? "Untitled", subtitle: sub,
                              photos: photos, commentCount: d["commentCount"] as? Int ?? 0)
        }
        let name = (j["profile"] as? [String: Any])?["display_name"] as? String ?? ""
        return FriendProfile(displayName: name, dumps: dumps)
    }

    /// GET /api/dump-comments?dumpId= (oldest first)
    func comments(on dumpId: String) async throws -> [DumpComment] {
        let j = try await call("GET", "dump-comments", query: ["dumpId": dumpId])
        return (j["comments"] as? [[String: Any]] ?? []).compactMap { c in
            guard let id = c["id"] as? String else { return nil }
            return DumpComment(id: id, body: c["body"] as? String ?? "", mine: c["mine"] as? Bool ?? false,
                               username: (c["author"] as? [String: Any])?["username"] as? String)
        }
    }

    /// POST /api/dump-comments { dumpId, body } (server trims + caps at 500)
    func postComment(on dumpId: String, body: String) async throws {
        _ = try await call("POST", "dump-comments", body: ["dumpId": dumpId, "body": String(body.prefix(500))])
    }

    func respond(_ row: FriendRow, accept: Bool) async {
        _ = try? await call("PATCH", "connections", body: ["id": row.connectionId, "status": accept ? "accepted" : "declined"])
        await loadFriends()
    }

    func addFriend(username: String) async throws {
        let name = username.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
        _ = try await call("POST", "connections", body: ["username": name])
        await loadFriends()
    }

    // MARK: Threads

    struct Thread { var messages: [DMMessage]; var blockingAvailable: Bool; var blockedByMe: Bool; var blockedByThem: Bool }

    /// Opening a thread marks received messages read server-side, so refresh the counts after.
    func thread(with id: String) async throws -> Thread {
        let j = try await call("GET", "dm", query: ["with": id])
        let msgs = (j["messages"] as? [[String: Any]] ?? []).compactMap { m -> DMMessage? in
            guard let mid = m["id"] as? String, let s = m["sender_id"] as? String else { return nil }
            return DMMessage(id: mid, senderId: s, body: m["body"] as? String ?? "")
        }
        Task { await refresh() }
        return Thread(messages: msgs, blockingAvailable: j["blockingAvailable"] as? Bool ?? false,
                      blockedByMe: j["blockedByMe"] as? Bool ?? false, blockedByThem: j["blockedByThem"] as? Bool ?? false)
    }

    func send(to id: String, text: String) async throws {
        _ = try await call("POST", "dm", body: ["recipientId": id, "body": String(text.prefix(SocialLogic.dmMaxLen))])
    }

    func setBlocked(_ block: Bool, with id: String) async throws {
        _ = try await call("PATCH", "dm", body: ["with": id, "action": block ? "block" : "unblock"])
    }

    // MARK: Username (same endpoint as web OnboardingFlow: GET availability, PATCH save)

    /// GET /api/check-username?username= -> {available, reason?}
    func checkUsername(_ username: String) async throws -> (available: Bool, reason: String?) {
        let j = try await call("GET", "check-username", query: ["username": username])
        return ((j["available"] as? Bool) ?? false, j["reason"] as? String)
    }

    /// PATCH /api/check-username {username, avatar_icon, avatar_color}; 409 = taken.
    func saveUsername(_ username: String, icon: String, color: String) async throws {
        _ = try await call("PATCH", "check-username", body: ["username": username, "avatar_icon": icon, "avatar_color": color])
    }

    // MARK: Instagram "Later" (auth user metadata, same keys as web: ig_pending / ig_handle)

    private let pendingKey = "ig_pending_unsynced"

    /// Tapped Later on the Instagram step. Reminders start the next day; stop once linked.
    func markInstagramLater() {
        UserDefaults.standard.set(SocialLogic.localDay(), forKey: "ig_pending_day")
        UserDefaults.standard.set(true, forKey: pendingKey)
        Task { await pushPendingIgState() }
    }

    func markInstagramLinked(_ handle: String) {
        UserDefaults.standard.removeObject(forKey: "ig_pending_day")
        UserDefaults.standard.set(true, forKey: pendingKey)
        UserDefaults.standard.set(handle, forKey: "ig_handle_pushed_value")
        Task { await pushPendingIgState() }
    }

    private func pushPendingIgState() async {
        let d = UserDefaults.standard
        guard d.bool(forKey: pendingKey), let jwt = await AuthManager.shared.jwt else { return }
        var data: [String: Any] = [:]
        if let day = d.string(forKey: "ig_pending_day") { data["ig_pending"] = day }
        else if let h = d.string(forKey: "ig_handle_pushed_value") { data["ig_handle"] = h; data["ig_pending"] = NSNull() }
        else { d.set(false, forKey: pendingKey); return }
        var req = URLRequest(url: URL(string: SupabaseClient.url + "/auth/v1/user")!)
        req.httpMethod = "PUT"
        req.timeoutInterval = 20
        SupabaseClient.shared.authHeaders(jwt: jwt).forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["data": data])
        if let (_, resp) = try? await URLSession.shared.data(for: req),
           (resp as? HTTPURLResponse)?.statusCode == 200 {
            d.set(false, forKey: pendingKey)   // retried next tick otherwise
        }
    }
}
