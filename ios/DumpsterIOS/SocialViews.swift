import SwiftUI

// MARK: - Bell (header) + notifications panel. Mirrors web NotificationBell.

struct NotificationBellButton: View {
    @ObservedObject private var social = SocialStore.shared
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var cs
    @State private var showPanel = false

    var body: some View {
        Button { showPanel = true } label: {
            Image(systemName: "bell")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.text(appState.colorMode, cs))
                .frame(width: 32, height: 32)
                .background(Theme.bg2(appState.colorMode, cs))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) {
                    if social.unreadCount > 0 {
                        Text(SocialLogic.badgeText(social.unreadCount))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Color(red: 0.94, green: 0.27, blue: 0.27))
                            .clipShape(Capsule())
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .accessibilityLabel(social.unreadCount > 0 ? "Notifications, \(social.unreadCount) unread" : "Notifications")
        .sheet(isPresented: $showPanel) {
            NotificationsPanel(isPresented: $showPanel)
                .environmentObject(appState)
                .presentationDetents([.medium, .large])
        }
    }
}

struct NotificationsPanel: View {
    @Binding var isPresented: Bool
    @ObservedObject private var social = SocialStore.shared
    @EnvironmentObject var appState: AppState

    var body: some View {
        let groups = SocialLogic.groupByDay(social.notifications, now: Date()) { $0.createdAt }
        VStack(spacing: 0) {
            HStack {
                Text("Notifications").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                Spacer()
                if social.unreadCount > 0 {
                    Button("Mark all read") { Task { await social.markAllRead() } }
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(appState.accentColor)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            Divider().background(Color.white.opacity(0.1))
            if social.notifications.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "info.circle").foregroundColor(.white.opacity(0.3))
                    Text("Nothing yet").font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                }.frame(maxWidth: .infinity).padding(.top, 40)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groups, id: \.label) { g in
                            Text(g.label.uppercased())
                                .font(.system(size: 10, weight: .bold)).tracking(0.8)
                                .foregroundColor(.white.opacity(0.4))
                                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
                            ForEach(g.items) { n in row(n) }
                        }
                    }
                }
            }
        }
        .background(Color(white: 0.055).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task { await social.refresh() }
    }

    private func row(_ n: AppNotification) -> some View {
        Button {
            isPresented = false
            Task { await social.open(n) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: n.symbol)
                    .font(.system(size: 12))
                    .foregroundColor(n.isRead ? .white.opacity(0.5) : appState.accentColor)
                    .frame(width: 28, height: 28)
                    .background(Color(white: 0.1)).clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(n.title)
                        .font(.system(size: 12.5, weight: n.isRead ? .medium : .bold))
                        .foregroundColor(.white.opacity(0.92)).multilineTextAlignment(.leading)
                    if let b = n.body, !b.isEmpty {
                        Text(b).font(.system(size: 11.5)).foregroundColor(.white.opacity(0.5)).lineLimit(1)
                    }
                    Text(SocialLogic.timeAgo(n.createdAt)).font(.system(size: 10)).foregroundColor(.white.opacity(0.4)).padding(.top, 1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(n.isRead ? Color.clear : appState.accentColor.opacity(0.06))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Friends screen (requests, add friend, Messages list). Mirrors web ConnectionsPanel messages section.

struct FriendsView: View {
    @Binding var isPresented: Bool
    @ObservedObject private var social = SocialStore.shared
    @EnvironmentObject var appState: AppState
    @State private var thread: SocialProfile?
    @State private var profileOf: SocialProfile?
    @State private var addName = ""
    @State private var addError: String?

    var body: some View {
        NavigationStack {
            List {
                let incoming = social.friends.filter { $0.status == "pending" && $0.incoming }
                if !incoming.isEmpty {
                    Section("Requests") {
                        ForEach(incoming) { r in
                            HStack {
                                Text(r.other.handle).foregroundColor(.white)
                                Spacer()
                                Button("Accept") { Task { await social.respond(r, accept: true) } }
                                    .foregroundColor(appState.accentColor).buttonStyle(.borderless)
                                Button("Decline") { Task { await social.respond(r, accept: false) } }
                                    .foregroundColor(.white.opacity(0.5)).buttonStyle(.borderless)
                            }
                        }
                    }
                }
                Section("Messages") {
                    if social.conversations.isEmpty {
                        Text("No messages yet. Tap a friend below to say hi.")
                            .font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                    }
                    ForEach(social.conversations) { c in
                        Button { thread = c.other } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.other.handle).font(.system(size: 14, weight: c.unread > 0 ? .bold : .medium)).foregroundColor(.white)
                                    Text((c.mine ? "You: " : "") + c.lastBody)
                                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.5)).lineLimit(1)
                                }
                                Spacer()
                                if c.unread > 0 {
                                    Text("\(c.unread)").font(.system(size: 11, weight: .bold)).foregroundColor(.black)
                                        .padding(.horizontal, 7).padding(.vertical, 2)
                                        .background(appState.accentColor).clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
                Section("Friends") {
                    let accepted = social.friends.filter { $0.status == "accepted" }
                    if accepted.isEmpty {
                        Text("No friends yet. Add one by username.").font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                    }
                    ForEach(accepted) { f in
                        HStack(spacing: 12) {
                            Button { thread = f.other } label: {
                                HStack {
                                    Text(f.other.handle).foregroundColor(.white)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            Button("View profile") { profileOf = f.other }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(appState.accentColor).buttonStyle(.borderless)
                            Button { thread = f.other } label: {
                                Image(systemName: "bubble.left").foregroundColor(appState.accentColor)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Message \(f.other.handle)")
                        }
                    }
                    HStack {
                        TextField("Add a friend by username", text: $addName)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .foregroundColor(.white)
                        Button("Add") {
                            Task {
                                do { try await social.addFriend(username: addName); addName = ""; addError = nil }
                                catch { addError = error.localizedDescription }
                            }
                        }
                        .disabled(addName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .foregroundColor(appState.accentColor).buttonStyle(.borderless)
                    }
                    if let addError { Text(addError).font(.system(size: 11.5)).foregroundColor(.red.opacity(0.9)) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(white: 0.055).ignoresSafeArea())
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { isPresented = false }.foregroundColor(appState.accentColor) } }
            .navigationDestination(item: $thread) { p in DMThreadView(other: p).environmentObject(appState) }
            .sheet(item: $profileOf) { p in FriendProfileSheet(person: p).environmentObject(appState) }
        }
        .preferredColorScheme(.dark)
        .task {
            await social.loadFriends()
            await social.refresh()
            if let id = social.openThreadWith {
                social.openThreadWith = nil
                thread = social.conversations.first { $0.id == id }?.other
                    ?? social.friends.first { $0.other.id == id }?.other
                    ?? SocialProfile(id: id, username: nil)
            }
        }
        .task(id: "poll") {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                await social.loadFriends()
            }
        }
    }
}


// MARK: - Thread. Mirrors web DMSheet: 2000-char cap, send, block/unblock, polls ~15s.

struct DMThreadView: View {
    let other: SocialProfile
    @EnvironmentObject var appState: AppState
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var social = SocialStore.shared
    @State private var thread = SocialStore.Thread(messages: [], blockingAvailable: false, blockedByMe: false, blockedByThem: false)
    @State private var draft = ""
    @State private var sending = false
    @State private var error: String?
    @State private var confirmBlock = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if thread.messages.isEmpty {
                            Text("Say hi to \(other.handle)").font(.system(size: 12)).foregroundColor(.white.opacity(0.35)).padding(.top, 40)
                        }
                        ForEach(thread.messages) { m in
                            let mine = m.senderId == auth.userId
                            HStack {
                                if mine { Spacer(minLength: 50) }
                                Text(m.body)
                                    .font(.system(size: 13.5))
                                    .foregroundColor(mine ? Color(white: 0.055) : .white.opacity(0.92))
                                    .padding(.horizontal, 13).padding(.vertical, 9)
                                    .background(mine ? appState.accentColor : Color(white: 0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                if !mine { Spacer(minLength: 50) }
                            }.id(m.id)
                        }
                    }.padding(16)
                }
                .onChange(of: thread.messages.last?.id) { _, id in if let id { proxy.scrollTo(id, anchor: .bottom) } }
            }
            if let error { Text(error).font(.system(size: 11.5)).foregroundColor(.red.opacity(0.9)).padding(.horizontal, 16) }
            if thread.blockedByMe || thread.blockedByThem {
                Text(thread.blockedByMe ? "You blocked this person." : "You can't message this person.")
                    .font(.system(size: 11.5)).foregroundColor(.white.opacity(0.5)).padding(.horizontal, 16).padding(.top, 6)
            }
            HStack(spacing: 8) {
                TextField("Message", text: $draft)
                    .foregroundColor(.white).padding(.horizontal, 14).padding(.vertical, 11)
                    .background(Color(white: 0.08)).clipShape(Capsule())
                    .disabled(thread.blockedByMe || thread.blockedByThem)
                    .onChange(of: draft) { _, v in if v.count > SocialLogic.dmMaxLen { draft = String(v.prefix(SocialLogic.dmMaxLen)) } }
                    .onSubmit { send() }
                Button { send() } label: {
                    Image(systemName: "paperplane.fill").foregroundColor(canSend ? Color(white: 0.055) : .white.opacity(0.3))
                        .frame(width: 40, height: 40)
                        .background(canSend ? appState.accentColor : Color(white: 0.1)).clipShape(Circle())
                }
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(Color(white: 0.055).ignoresSafeArea())
        .navigationTitle(other.handle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if thread.blockingAvailable {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(thread.blockedByMe ? "Unblock" : "Block") {
                        if thread.blockedByMe { toggleBlock(false) } else { confirmBlock = true }
                    }.foregroundColor(thread.blockedByMe ? appState.accentColor : .white.opacity(0.6))
                }
            }
        }
        .alert("Block \(other.handle)?", isPresented: $confirmBlock) {
            Button("Block", role: .destructive) { toggleBlock(true) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Neither of you can message the other until you unblock.") }
        .task { await load() }
        .task(id: "poll") {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                await load()
            }
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending && !thread.blockedByMe && !thread.blockedByThem
    }

    private func load() async {
        if let t = try? await social.thread(with: other.id) { thread = t }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        sending = true; error = nil; draft = ""
        Task {
            do { try await social.send(to: other.id, text: text); await load() }
            catch { draft = text; self.error = error.localizedDescription }   // keep what they typed
            sending = false
        }
    }

    private func toggleBlock(_ block: Bool) {
        Task {
            do { try await social.setBlocked(block, with: other.id); thread.blockedByMe = block }
            catch { self.error = "Blocking isn't available yet." }
        }
    }
}


// MARK: - Public / Private row for the dump options sheet. Mirrors web DumpActionSheet's toggle row:
// optimistic flip, reverted if the server refuses. Self-contained so DumpMenuSheet only needs one line.

/// iOS dumps stay on this device (Lee's decision: nothing is uploaded from iOS), so there is no share switch here.
/// Web-made dumps can still be public; friends see those in their profile sheet below.
struct DumpPublicToggleRow: View {
    let dump: PhotoDump

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "lock")
                .font(.system(size: 16))
                .foregroundColor(.white)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("Private").font(.system(size: 16)).foregroundColor(.white)
                Text("Stays on this device")
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
            }
            Spacer()
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
    }
}

// MARK: - Friend profile. Mirrors web FriendProfileSheet: hero + stats, public dumps, tap one for the
// big photo carousel + "Ideas & comments". No photo numbers anywhere.

struct FriendProfileSheet: View {
    let person: SocialProfile
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var social = SocialStore.shared
    @State private var profile: SocialStore.FriendProfile?
    @State private var error: String?
    @State private var open: SocialStore.FriendDump?
    @State private var comments: [SocialStore.DumpComment] = []
    @State private var commentsError: String?
    @State private var draft = ""
    @State private var sending = false
    @State private var sendError: String?

    private var avatar: Color { Color(hex: person.avatarColor ?? "#C8A96E") }
    private var initial: String { String((person.username ?? "?").prefix(1)).uppercased() }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().background(Color.white.opacity(0.1))
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let open { detail(open) } else { list }
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
            }
            if open != nil { composer }
        }
        .background(Color(white: 0.055).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .task { await loadProfile() }
    }

    // MARK: Pieces

    private var topBar: some View {
        HStack(spacing: 10) {
            if open != nil {
                Button { open = nil } label: { Image(systemName: "chevron.left").foregroundColor(.white.opacity(0.6)) }
                    .accessibilityLabel("Back")
            }
            Text(String(initial))
                .font(.system(size: 12, weight: .bold)).foregroundColor(Color(white: 0.055))
                .frame(width: 32, height: 32).background(avatar).clipShape(Circle())
            Text(open?.title ?? person.handle)
                .font(.system(size: 15, weight: .bold)).foregroundColor(.white).lineLimit(1)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.6))
                    .frame(width: 30, height: 30).background(Color(white: 0.1)).clipShape(Circle())
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    @ViewBuilder private var list: some View {
        VStack(spacing: 4) {
            Text(initial)
                .font(.system(size: 32, weight: .heavy)).foregroundColor(Color(white: 0.055))
                .frame(width: 84, height: 84)
                .background(LinearGradient(colors: [avatar, Color(white: 0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(appState.accentColor, lineWidth: 2))
                .padding(.bottom, 8)
            Text(person.handle).font(.system(size: 20, weight: .heavy)).foregroundColor(.white)
            if let n = profile?.displayName, !n.isEmpty {
                Text(n).font(.system(size: 13)).foregroundColor(.white.opacity(0.55))
            }
            if let p = profile {
                HStack(spacing: 28) {
                    stat(p.dumps.count, "Dumps")
                    stat(p.dumps.reduce(0) { $0 + $1.photos.count }, "Photos")
                    stat(p.dumps.reduce(0) { $0 + $1.commentCount }, "Comments")
                }.padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity).padding(.bottom, 22)

        if let error {
            Text(error).font(.system(size: 13)).foregroundColor(.white.opacity(0.6))
        } else if let p = profile {
            if p.dumps.isEmpty {
                Text("\(person.handle) hasn't shared any dumps yet.").font(.system(size: 13)).foregroundColor(.white.opacity(0.5))
            }
            ForEach(p.dumps) { d in dumpCard(d) }
        } else {
            ProgressView().frame(maxWidth: .infinity)
        }
    }

    private func stat(_ n: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(n)").font(.system(size: 18, weight: .heavy)).foregroundColor(.white)
            Text(label.uppercased()).font(.system(size: 10)).tracking(0.8).foregroundColor(.white.opacity(0.45))
        }
    }

    private func dumpCard(_ d: SocialStore.FriendDump) -> some View {
        Button { openDump(d) } label: {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(d.photos.prefix(6)) { p in photo(p.url).frame(width: 168, height: 216).clipShape(RoundedRectangle(cornerRadius: 12)) }
                    }
                }
                .padding(.bottom, 12)
                Text(d.title).font(.system(size: 17, weight: .heavy)).foregroundColor(.white)
                if let sub = d.subtitle { Text(sub).font(.system(size: 13)).foregroundColor(.white.opacity(0.55)).padding(.top, 2) }
                Text("\(d.photos.count) photos · " + (d.commentCount > 0 ? "\(d.commentCount) comment\(d.commentCount == 1 ? "" : "s")" : "Tap to comment"))
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(appState.accentColor).padding(.top, 8)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 14)
    }

    private func photo(_ url: URL?) -> some View {
        AsyncImage(url: url) { phase in
            if let img = phase.image { img.resizable().scaledToFill() }
            else { Color(white: 0.12).overlay(phase.error != nil ? Image(systemName: "photo").foregroundColor(.white.opacity(0.25)) : nil) }
        }
    }

    @ViewBuilder private func detail(_ d: SocialStore.FriendDump) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(d.photos) { p in
                    photo(p.url)
                        .containerRelativeFrame(.horizontal) { w, _ in min(w * 0.82, 420) }
                        .aspectRatio(4.0 / 5.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .padding(.horizontal, -20).contentMargins(.horizontal, 20, for: .scrollContent)
        .padding(.bottom, 18)

        Text("IDEAS & COMMENTS").font(.system(size: 10, weight: .bold)).tracking(1).foregroundColor(.white.opacity(0.5)).padding(.bottom, 8)
        if let commentsError {
            Text(commentsError).font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
        } else if comments.isEmpty {
            Text("No comments yet — leave the first idea.").font(.system(size: 12)).foregroundColor(.white.opacity(0.4))
        }
        ForEach(comments) { c in
            (Text(c.mine ? "You" : "@" + (c.username ?? "someone")).fontWeight(.bold)
                .foregroundColor(c.mine ? appState.accentColor : .white)
             + Text("  " + c.body).foregroundColor(.white.opacity(0.9)))
                .font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 10)
        }
    }

    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending }

    private var composer: some View {
        VStack(spacing: 6) {
            if let sendError { Text(sendError).font(.system(size: 11.5)).foregroundColor(.red.opacity(0.9)) }
            HStack(spacing: 8) {
                TextField("Leave an idea for this dump…", text: $draft)
                    .foregroundColor(.white).padding(.horizontal, 14).padding(.vertical, 11)
                    .background(Color(white: 0.08)).clipShape(RoundedRectangle(cornerRadius: 12))
                    .onChange(of: draft) { _, v in if v.count > 500 { draft = String(v.prefix(500)) } }
                    .onSubmit { send() }
                Button { send() } label: {
                    Image(systemName: "paperplane.fill").foregroundColor(canSend ? Color.black : .white.opacity(0.3))
                        .frame(width: 44, height: 44)
                        .background(canSend ? appState.accentColor : Color(white: 0.1)).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!canSend)
                .accessibilityLabel("Send comment")
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Color(white: 0.055))
        .overlay(alignment: .top) { Divider().background(Color.white.opacity(0.1)) }
    }

    // MARK: Actions

    private func loadProfile() async {
        do { profile = try await social.profile(of: person.id); error = nil }
        catch { self.error = "Couldn't load this profile." + ((error as? SocialError).map { " " + $0.message } ?? "") }
    }

    private func openDump(_ d: SocialStore.FriendDump) {
        open = d; comments = []; draft = ""; sendError = nil; commentsError = nil
        Task { await loadComments(d.id) }
    }

    private func loadComments(_ dumpId: String) async {
        do { comments = try await social.comments(on: dumpId); commentsError = nil }
        catch { commentsError = "Couldn't load comments." }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend, let d = open else { return }
        sending = true; sendError = nil; draft = ""
        Task {
            do {
                try await social.postComment(on: d.id, body: text)
                await loadComments(d.id)
                if let i = profile?.dumps.firstIndex(where: { $0.id == d.id }) { profile?.dumps[i].commentCount = comments.count }
            } catch {
                draft = text   // keep what they typed
                sendError = (error as? SocialError)?.message ?? "Couldn't post your comment."
            }
            sending = false
        }
    }
}
