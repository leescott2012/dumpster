import SwiftUI

/// Connections, friend profiles and dump comments. Port of ConnectionsPanel.tsx,
/// FriendProfileSheet.tsx and the /api/connections + /api/dump-comments endpoints.

// MARK: - API

private enum SocialAPI {
    static let base: URL = {
        if let o = Bundle.main.object(forInfoDictionaryKey: "DumpsterAPIBaseURL") as? String, let u = URL(string: o) { return u }
        return URL(string: "https://dumpster-web-manus.vercel.app")!
    }()

    static func request(_ path: String, query: [String: String] = [:], method: String = "GET", body: [String: Any]? = nil) async throws -> (Int, [String: Any]) {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        if let jwt = await AuthManager.shared.jwt { req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return ((resp as? HTTPURLResponse)?.statusCode ?? 0, json)
    }
}

struct SocialPerson: Identifiable, Hashable {
    let id: String
    let username: String
    let color: String?
    init?(_ d: [String: Any]) {
        guard let id = d["id"] as? String else { return nil }
        self.id = id
        self.username = (d["username"] as? String) ?? "?"
        self.color = d["avatar_color"] as? String
    }
}

private struct ConnRow: Identifiable {
    let id: String
    let status: String
    let iAmAddressee: Bool
    let other: SocialPerson
}

// MARK: - Connections

struct ConnectionsView: View {
    private let gold = Color(hex: "#C8A96E")
    @State private var query = ""
    @State private var results: [SocialPerson] = []
    @State private var fuzzy = false
    @State private var searched = ""
    @State private var searching = false
    @State private var rows: [ConnRow] = []
    @State private var sent = Set<String>()
    @State private var searchTask: Task<Void, Never>?

    private var myId: String { AuthManager.shared.userId ?? "" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Search by username", text: $query)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                    .onChange(of: query) { _, _ in scheduleSearch() }

                if !searching && !searched.isEmpty && results.isEmpty {
                    Text("No one found for @\(searched). Check the spelling — try fewer letters.")
                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                }
                if fuzzy && !results.isEmpty {
                    Text("No exact match for @\(searched) — did you mean:")
                        .font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
                }
                ForEach(results) { p in
                    let already = sent.contains(p.username.lowercased()) || rows.contains { $0.other.id == p.id }
                    HStack(spacing: 10) {
                        avatar(p)
                        Text("@\(p.username)").foregroundColor(.white)
                        Spacer()
                        Button(already ? "Sent" : "Add") { Task { await add(p) } }
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(already ? Color.white.opacity(0.06) : gold.opacity(0.2)))
                            .foregroundColor(already ? .white.opacity(0.4) : gold)
                            .disabled(already)
                    }
                }

                section("REQUESTS", rows.filter { $0.status == "pending" && $0.iAmAddressee }) { r in
                    HStack(spacing: 10) {
                        avatar(r.other); Text("@\(r.other.username)").foregroundColor(.white); Spacer()
                        Button("Accept") { Task { await respond(r, "accepted") } }.foregroundColor(gold)
                        Button("Decline") { Task { await respond(r, "declined") } }.foregroundColor(.white.opacity(0.5))
                    }.font(.system(size: 12, weight: .semibold))
                }

                let accepted = rows.filter { $0.status == "accepted" }
                Text("CONNECTIONS").font(.system(size: 10, weight: .heavy)).tracking(1.2).foregroundColor(.white.opacity(0.4))
                if accepted.isEmpty {
                    Text("No connections yet — search above to find people.")
                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.4))
                }
                ForEach(accepted) { r in
                    NavigationLink { FriendProfileView(person: r.other) } label: {
                        HStack(spacing: 10) {
                            avatar(r.other)
                            Text("@\(r.other.username)").foregroundColor(.white)
                            Spacer()
                            Text("View profile").font(.system(size: 11)).foregroundColor(gold)
                            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundColor(.white.opacity(0.3))
                        }
                    }
                }

                section("PENDING", rows.filter { $0.status == "pending" && !$0.iAmAddressee }) { r in
                    HStack(spacing: 10) {
                        avatar(r.other); Text("@\(r.other.username)").foregroundColor(.white.opacity(0.5)); Spacer()
                        Text("Pending").font(.system(size: 11)).foregroundColor(.white.opacity(0.4))
                    }
                }
            }
            .padding(20)
        }
        .background(Color(white: 0.05).ignoresSafeArea())
        .navigationTitle("Connections")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [ConnRow], @ViewBuilder row: @escaping (ConnRow) -> some View) -> some View {
        if !items.isEmpty {
            Text(title).font(.system(size: 10, weight: .heavy)).tracking(1.2).foregroundColor(.white.opacity(0.4))
            ForEach(items) { row($0) }
        }
    }

    private func avatar(_ p: SocialPerson) -> some View {
        Text(String(p.username.prefix(1)).uppercased())
            .font(.system(size: 12, weight: .bold)).foregroundColor(.black)
            .frame(width: 32, height: 32)
            .background(Circle().fill(p.color.map { Color(hex: $0) } ?? Color.gray))
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "^@+", with: "", options: .regularExpression)
        guard !q.isEmpty else { results = []; searched = ""; fuzzy = false; searching = false; return }
        searching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            let (code, json) = (try? await SocialAPI.request("api/connections", query: ["mode": "search", "q": q])) ?? (0, [:])
            guard !Task.isCancelled else { return }
            results = code == 200 ? ((json["results"] as? [[String: Any]]) ?? []).compactMap(SocialPerson.init) : []
            fuzzy = (json["fuzzy"] as? Bool) ?? false
            searched = q
            searching = false
        }
    }

    private func load() async {
        guard let (code, json) = try? await SocialAPI.request("api/connections", query: ["mode": "list"]), code == 200 else { return }
        rows = ((json["connections"] as? [[String: Any]]) ?? []).compactMap { d in
            guard let id = d["id"] as? String, let status = d["status"] as? String,
                  let o = d["other"] as? [String: Any], let other = SocialPerson(o) else { return nil }
            return ConnRow(id: id, status: status, iAmAddressee: (d["addressee_id"] as? String) == myId, other: other)
        }
    }

    private func add(_ p: SocialPerson) async {
        sent.insert(p.username.lowercased())
        _ = try? await SocialAPI.request("api/connections", method: "POST", body: ["username": p.username])
        await load()
    }

    private func respond(_ r: ConnRow, _ status: String) async {
        _ = try? await SocialAPI.request("api/connections", method: "PATCH", body: ["id": r.id, "status": status])
        await load()
    }
}

// MARK: - Friend profile

private struct FriendDump: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let photoURLs: [URL]
    let commentCount: Int
}

struct FriendProfileView: View {
    let person: SocialPerson
    private let gold = Color(hex: "#C8A96E")
    @State private var dumps: [FriendDump]?
    @State private var displayName = ""
    @State private var error = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                hero
                if !error.isEmpty { Text(error).foregroundColor(.white.opacity(0.6)) }
                else if dumps == nil { ProgressView().tint(gold) }
                else if dumps?.isEmpty == true {
                    Text("@\(person.username) hasn't shared any dumps yet.").foregroundColor(.white.opacity(0.5))
                }
                ForEach(dumps ?? []) { d in
                    NavigationLink { FriendDumpView(dump: d) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(Array(d.photoURLs.prefix(6).enumerated()), id: \.offset) { _, u in
                                        AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.06) }
                                            .frame(width: 168, height: 216).clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                }
                            }
                            Text(d.title).font(.system(size: 17, weight: .heavy)).foregroundColor(.white)
                            if let s = d.subtitle { Text(s).font(.system(size: 13)).foregroundColor(.white.opacity(0.5)) }
                            Text("\(d.photoURLs.count) photos · " + (d.commentCount > 0 ? "\(d.commentCount) comment\(d.commentCount == 1 ? "" : "s")" : "Tap to comment"))
                                .font(.system(size: 11)).foregroundColor(gold)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.05)))
                    }
                }
            }
            .padding(20)
        }
        .background(Color(white: 0.05).ignoresSafeArea())
        .navigationTitle("@\(person.username)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var hero: some View {
        VStack(spacing: 6) {
            Text(String(person.username.prefix(1)).uppercased())
                .font(.system(size: 32, weight: .heavy)).foregroundColor(.black)
                .frame(width: 84, height: 84)
                .background(Circle().fill(LinearGradient(colors: [person.color.map { Color(hex: $0) } ?? gold, Color(white: 0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(Circle().stroke(gold, lineWidth: 2))
            Text("@\(person.username)").font(.system(size: 20, weight: .heavy)).foregroundColor(.white)
            if !displayName.isEmpty { Text(displayName).font(.system(size: 13)).foregroundColor(.white.opacity(0.5)) }
            if let dumps {
                HStack(spacing: 28) {
                    stat(dumps.count, "DUMPS")
                    stat(dumps.reduce(0) { $0 + $1.photoURLs.count }, "PHOTOS")
                    stat(dumps.reduce(0) { $0 + $1.commentCount }, "COMMENTS")
                }.padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 10)
    }

    private func stat(_ n: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(n)").font(.system(size: 18, weight: .heavy)).foregroundColor(.white)
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(1).foregroundColor(.white.opacity(0.4))
        }
    }

    private func load() async {
        guard let (code, json) = try? await SocialAPI.request("api/connections", query: ["mode": "profile", "userId": person.id]) else {
            error = "Couldn't load this profile."; return
        }
        guard code == 200 else { error = (json["error"] as? String) ?? "Couldn't load this profile."; return }
        displayName = ((json["profile"] as? [String: Any])?["display_name"] as? String) ?? ""
        dumps = ((json["dumps"] as? [[String: Any]]) ?? []).compactMap { d in
            guard let id = d["id"] as? String, let title = d["title"] as? String else { return nil }
            let urls = ((d["photos"] as? [[String: Any]]) ?? []).compactMap { ($0["url"] as? String).flatMap(URL.init) }
            return FriendDump(id: id, title: title, subtitle: d["subtitle"] as? String, photoURLs: urls, commentCount: (d["commentCount"] as? Int) ?? 0)
        }
    }
}

// MARK: - Dump + comments

private struct DumpComment: Identifiable {
    let id: String
    let body: String
    let mine: Bool
    let author: String
}

private struct FriendDumpView: View {
    let dump: FriendDump
    private let gold = Color(hex: "#C8A96E")
    @State private var comments: [DumpComment] = []
    @State private var text = ""
    @State private var sending = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(dump.photoURLs.enumerated()), id: \.offset) { i, u in
                                AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.06) }
                                    .frame(width: 300, height: 375)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .overlay(alignment: .topTrailing) {
                                        Text("\(i + 1) / \(dump.photoURLs.count)")
                                            .font(.system(size: 11)).foregroundColor(.white)
                                            .padding(.horizontal, 9).padding(.vertical, 3)
                                            .background(Capsule().fill(Color.black.opacity(0.6))).padding(10)
                                    }
                            }
                        }
                    }
                    Text("IDEAS & COMMENTS").font(.system(size: 10, weight: .heavy)).tracking(1.2).foregroundColor(.white.opacity(0.4))
                    if comments.isEmpty {
                        Text("No comments yet — leave the first idea.").font(.system(size: 12)).foregroundColor(.white.opacity(0.4))
                    }
                    ForEach(comments) { c in
                        (Text(c.mine ? "You " : "@\(c.author) ").bold().foregroundColor(c.mine ? gold : .white)
                         + Text(c.body).foregroundColor(.white.opacity(0.9)))
                            .font(.system(size: 13))
                    }
                }
                .padding(20)
            }
            HStack(spacing: 8) {
                TextField("Leave an idea for this dump…", text: $text)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                    .submitLabel(.send).onSubmit { Task { await send() } }
                Button { Task { await send() } } label: {
                    Image(systemName: "paperplane.fill").foregroundColor(.black)
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 12).fill(text.trimmingCharacters(in: .whitespaces).isEmpty ? Color.white.opacity(0.1) : gold))
                }
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || sending)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .background(Color(white: 0.05).ignoresSafeArea())
        .navigationTitle(dump.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        guard let (code, json) = try? await SocialAPI.request("api/dump-comments", query: ["dumpId": dump.id]), code == 200 else { return }
        comments = ((json["comments"] as? [[String: Any]]) ?? []).compactMap { d in
            guard let id = d["id"] as? String, let body = d["body"] as? String else { return nil }
            let author = ((d["author"] as? [String: Any])?["username"] as? String) ?? "?"
            return DumpComment(id: id, body: body, mine: (d["mine"] as? Bool) ?? false, author: author)
        }
    }

    private func send() async {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !sending else { return }
        sending = true
        let (code, _) = (try? await SocialAPI.request("api/dump-comments", method: "POST", body: ["dumpId": dump.id, "body": body])) ?? (0, [:])
        sending = false
        if code == 200 { text = ""; await load() }
    }
}
