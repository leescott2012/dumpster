import SwiftUI
import SwiftData
import PhotosUI

// Native mirror of client/src/components/OnboardingFlow.tsx — same step order, copy and rules.
// Blocking (no dismiss). Phone verification (optional on web) is skipped on iOS: sign-in here is email-code only.

/// Photos required before a user can finish setup (web: MIN_PHOTOS).
let onboardingMinPhotos = 30

/// Mirror of web avatarIcons.ts. Each name is the exact lucide icon (same name string web stores in
/// profiles.avatar_icon), bundled as the real lucide SVG: Assets.xcassets/avatar-<name>.imageset.
enum AvatarCatalog {
    static let iconNames = ["camera", "image", "star", "heart", "sun", "moon", "zap", "flame",
                            "sparkles", "palette", "music", "coffee", "rocket", "feather", "aperture", "smile"]
    static let colors = ["#f5c518", "#ef4444", "#f97316", "#eab308", "#22c55e", "#06b6d4", "#3b82f6", "#8b5cf6", "#ec4899", "#9ca3af"]
}

/// The single place an avatar is drawn (onboarding, friends, DMs, friend profile). Shows the lucide icon for a known
/// `icon` name, otherwise the username initial (what web does for accounts with no icon).
struct AvatarView: View {
    let icon: String?
    let colorHex: String?
    let initial: String
    let size: CGFloat
    var glyphRatio: CGFloat = 0.5
    var fallbackColor = "#333333"

    var body: some View {
        ZStack {
            Circle().fill(Color(hex: colorHex ?? fallbackColor))
            if let icon, AvatarCatalog.iconNames.contains(icon) {
                Image("avatar-\(icon)").renderingMode(.template).resizable().scaledToFit()
                    .frame(width: size * glyphRatio, height: size * glyphRatio)
                    .foregroundColor(Color(white: 0.055))
            } else {
                Text(initial).font(.system(size: size * 0.38, weight: .bold)).foregroundColor(Color(white: 0.055))
            }
        }
        .frame(width: size, height: size)
    }
}

/// Reads the signed-in user's profile row to decide whether to show the flow (web: Home.tsx `onboardingOpen`).
@MainActor
enum OnboardingGate {
    /// nil = couldn't tell (offline / error) -> don't trap the user behind the flow.
    static func load() async -> (hasUsername: Bool, completed: Bool)? {
        guard let uid = AuthManager.shared.userId, let jwt = AuthManager.shared.jwt else { return nil }
        do {
            let data = try await SupabaseClient.shared.get(table: "profiles", query: "id=eq.\(uid)&select=username,onboarding_completed_at", jwt: jwt)
            let row = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            let name = (row["username"] as? String) ?? ""
            return (!name.isEmpty, !(row["onboarding_completed_at"] is NSNull) && row["onboarding_completed_at"] != nil)
        } catch SupabaseClient.SupabaseError.noRow {
            return (false, false)
        } catch {
            return nil
        }
    }
}

struct OnboardingView: View {
    let hasUsername: Bool
    /// Pool size (non-video photos) — drives the photo-step progress and gate.
    let poolCount: Int
    /// true = "Group them for me", false = "I'll pick them myself".
    let onFinish: (_ useAI: Bool) -> Void

    private enum Step { case username, photos, taste, finish }
    private enum CheckState { case idle, checking, available, taken, invalid }

    @Environment(\.modelContext) private var modelContext
    @AppStorage("ai_style_profile") private var taste = ""
    @State private var step: Step

    // Step 1
    @State private var username = ""
    @State private var checkState: CheckState = .idle
    @State private var checkReason: String?
    @State private var icon = AvatarCatalog.iconNames[0]
    @State private var color = AvatarCatalog.colors[0]
    @State private var saving = false
    @State private var saveError: String?

    // Step 2
    @State private var pickerItems: [PhotosPickerItem] = []

    // Step 3
    @State private var igInput = ""
    @State private var scrubbing = false
    @State private var scrubbed = false
    @State private var scrubError: String?

    // Step 4
    @State private var finishing = false

    private let green = Color(red: 0.29, green: 0.87, blue: 0.5)
    private let red = Color(red: 0.94, green: 0.27, blue: 0.27)

    init(hasUsername: Bool, poolCount: Int, onFinish: @escaping (Bool) -> Void) {
        self.hasUsername = hasUsername
        self.poolCount = poolCount
        self.onFinish = onFinish
        _step = State(initialValue: hasUsername ? .photos : .username)
    }

    private var steps: [Step] { hasUsername ? [.photos, .taste, .finish] : [.username, .photos, .taste, .finish] }
    private var photosLeft: Int { max(0, onboardingMinPhotos - poolCount) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
                .contentShape(Rectangle()) // swallow taps: blocking flow
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    progress
                    switch step {
                    case .username: usernameStep
                    case .photos: photosStep
                    case .taste: tasteStep
                    case .finish: finishStep
                    }
                }
                .padding(28)
                .background(Color(red: 0.055, green: 0.055, blue: 0.055))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(white: 0.16)))
                .frame(maxWidth: 420)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.dark)
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPickedPhotoItems(items, into: modelContext); pickerItems.removeAll() }
        }
        .task(id: username) { await checkUsername() }
    }

    // MARK: Chrome

    private var progress: some View {
        let idx = steps.firstIndex(of: step) ?? 0
        return HStack(spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, _ in
                Capsule().fill(i <= idx ? Color.white : Color(white: 0.16)).frame(height: 3)
            }
        }.padding(.bottom, 22)
    }

    private func title(_ t: String) -> some View {
        Text(t).font(.system(size: 19, weight: .heavy)).foregroundColor(.white).padding(.bottom, 6)
    }

    private func sub(_ t: String) -> some View {
        Text(t).font(.system(size: 12)).foregroundColor(Color(white: 0.47)).lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true).padding(.bottom, 20)
    }

    private func err(_ t: String) -> some View {
        Text(t).font(.system(size: 11)).foregroundColor(red).padding(.bottom, 10)
    }

    private func primary(_ label: String, enabled: Bool, busy: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group { if busy { ProgressView().tint(.black) } else { Text(label) } }
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(enabled ? .black : Color(white: 0.4))
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(enabled ? Color.white : Color(white: 0.16))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(!enabled).padding(.top, 8)
    }

    private func field(_ content: some View) -> some View {
        content
            .foregroundColor(Color(white: 0.91))
            .padding(13)
            .background(Color(white: 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(white: 0.16)))
    }

    // MARK: Step 1 — username + avatar

    private var usernameStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Choose a username")
            sub("Needed so other users can find and connect with you. 3-20 characters, letters/numbers/underscore.")

            AvatarView(icon: icon, colorHex: color, initial: "?", size: 64, glyphRatio: 0.45)
                .frame(maxWidth: .infinity).padding(.bottom, 18)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 8), count: 8), spacing: 8) {
                ForEach(AvatarCatalog.iconNames, id: \.self) { name in
                    let sel = name == icon
                    Button { icon = name } label: {
                        Image("avatar-\(name)").renderingMode(.template).resizable().scaledToFit()
                            .frame(width: 16, height: 16)
                            .foregroundColor(sel ? Color(white: 0.055) : Color(white: 0.54))
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(sel ? Color(hex: color) : Color(white: 0.1)))
                            .overlay(Circle().stroke(sel ? Color.white : Color(white: 0.16), lineWidth: sel ? 2 : 1))
                    }
                }
            }
            .frame(maxWidth: .infinity).padding(.bottom, 14)

            HStack(spacing: 8) {
                ForEach(AvatarCatalog.colors, id: \.self) { c in
                    Button { color = c } label: {
                        Circle().fill(Color(hex: c)).frame(width: 22, height: 22)
                            .overlay(Circle().stroke(c == color ? Color.white : Color.white.opacity(0.2), lineWidth: c == color ? 2 : 1))
                    }
                }
            }
            .frame(maxWidth: .infinity).padding(.bottom, 22)

            HStack {
                field(TextField("username", text: $username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .onChange(of: username) { _, v in
                        let f = v.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
                        if f != v { username = f }
                    })
                .overlay(alignment: .trailing) {
                    Group {
                        switch checkState {
                        case .checking: ProgressView().scaleEffect(0.7)
                        case .available: Image(systemName: "checkmark").foregroundColor(green)
                        case .taken, .invalid: Image(systemName: "xmark").foregroundColor(red)
                        case .idle: EmptyView()
                        }
                    }.padding(.trailing, 12)
                }
            }
            .padding(.bottom, 8)
            if let checkReason, checkState == .taken || checkState == .invalid { err(checkReason) }
            if let saveError { err(saveError) }

            primary("Continue", enabled: checkState == .available && !saving, busy: saving) { Task { await saveUsername() } }
        }
    }

    // Live availability check — 400ms debounce, same as web. GET /api/check-username?username=
    private func checkUsername() async {
        let trimmed = username.trimmingCharacters(in: .whitespaces)
        guard step == .username else { return }
        if trimmed.count < 3 { checkState = .idle; return }
        checkState = .checking
        try? await Task.sleep(nanoseconds: 400_000_000)
        if Task.isCancelled { return }
        do {
            let r = try await SocialStore.shared.checkUsername(trimmed)
            if Task.isCancelled { return }
            if r.available { checkState = .available; checkReason = nil }
            else { checkState = r.reason != nil ? .invalid : .taken; checkReason = r.reason ?? "That username is taken" }
        } catch {
            if !Task.isCancelled { checkState = .idle }
        }
    }

    // PATCH /api/check-username — saves username + avatar_icon + avatar_color to the profile.
    private func saveUsername() async {
        guard checkState == .available else { return }
        saving = true; saveError = nil
        defer { saving = false }
        do {
            try await SocialStore.shared.saveUsername(username.trimmingCharacters(in: .whitespaces), icon: icon, color: color)
            withAnimation { step = .photos }
        } catch let e as SocialError {
            saveError = e.message.isEmpty ? "Couldn't save — try another username" : e.message
            checkState = .taken
        } catch {
            saveError = "Network error — try again"
        }
    }

    // MARK: Step 2 — photos

    private var photosStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Add your photos")
            sub("Dumpster needs a library to work with. Pick at least \(onboardingMinPhotos) photos — the more you add, the better it gets at grouping and captioning them.")

            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(poolCount)").font(.system(size: 34, weight: .heavy)).foregroundColor(.white)
                    Text(" / \(onboardingMinPhotos)").font(.system(size: 18, weight: .semibold)).foregroundColor(Color(white: 0.33))
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(white: 0.1))
                        Capsule().fill(photosLeft == 0 ? green : Color.white)
                            .frame(width: g.size.width * min(1, CGFloat(poolCount) / CGFloat(onboardingMinPhotos)))
                            .animation(.easeOut(duration: 0.4), value: poolCount)
                    }
                }.frame(height: 4).padding(.vertical, 12)
                Text(photosLeft == 0 ? "Nice — that's enough to get started" : "\(photosLeft) more to go")
                    .font(.system(size: 12)).foregroundColor(photosLeft == 0 ? green : Color(white: 0.47))
            }
            .frame(maxWidth: .infinity).padding(20)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(white: 0.16)))
            .padding(.bottom, 18)

            PhotosPicker(selection: $pickerItems, maxSelectionCount: 50, selectionBehavior: .ordered, matching: .images) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 14))
                    Text("Choose photos").font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(Color(white: 0.91))
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(Color(white: 0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(white: 0.16)))
            }.padding(.bottom, 10)

            primary(photosLeft == 0 ? "Continue" : "Add \(photosLeft) more to continue", enabled: poolCount >= onboardingMinPhotos) {
                withAnimation { step = .taste }
            }
        }
    }

    // MARK: Step 3 — style

    private var tasteStep: some View {
        let trimmedTaste = taste.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 0) {
            title("Your style")
            sub("This teaches Dumpster how to caption and group your photos the way you'd want. Pull it from an Instagram account, or just describe it yourself.")

            Text("YOUR INSTAGRAM").font(.system(size: 11)).tracking(0.4).foregroundColor(Color(white: 0.47)).padding(.bottom, 8)
            HStack(spacing: 8) {
                field(HStack(spacing: 8) {
                    Image(systemName: "camera").font(.system(size: 14)).foregroundColor(Color(white: 0.4))
                    TextField("@username", text: $igInput)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onChange(of: igInput) { _, _ in scrubbed = false }
                })
                let canScan = !igInput.trimmingCharacters(in: .whitespaces).isEmpty && !scrubbing
                Button { Task { await scan() } } label: {
                    HStack(spacing: 6) {
                        if scrubbing { ProgressView().tint(Color(red: 0.02, green: 0.13, blue: 0.06)).scaleEffect(0.7) }
                        else { Image(systemName: "sparkles").font(.system(size: 13)) }
                        Text(scrubbing ? "SCANNING" : "SCAN").font(.system(size: 13, weight: .heavy)).tracking(0.8)
                    }
                    .foregroundColor(Color(red: 0.02, green: 0.13, blue: 0.06))
                    .padding(.horizontal, 16).frame(maxHeight: .infinity)
                    .background(Color(red: 0.13, green: 0.77, blue: 0.37).opacity(canScan || scrubbing ? 1 : 0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!canScan)
            }
            .fixedSize(horizontal: false, vertical: true).padding(.bottom, 6)
            if let scrubError { err(scrubError) }

            Text("YOUR STYLE PROFILE").font(.system(size: 11)).tracking(0.4).foregroundColor(Color(white: 0.47)).padding(.top, 16).padding(.bottom, 8)
            field(ZStack(alignment: .topLeading) {
                if taste.isEmpty {
                    Text("e.g. moody film-grain city shots, dry one-line captions, never use emoji")
                        .foregroundColor(Color(white: 0.35)).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                }
                TextEditor(text: $taste).scrollContentBackground(.hidden).frame(minHeight: 110)
            })

            primary(!scrubbed ? "Enter your Instagram and tap SCAN" : trimmedTaste.count < 10 ? "Describe your style to continue" : "Continue",
                    enabled: scrubbed && trimmedTaste.count >= 10) { withAnimation { step = .finish } }

            Button {
                SocialStore.shared.markInstagramLater()
                withAnimation { step = .finish }
            } label: {
                Text("Later").font(.system(size: 13, weight: .semibold)).foregroundColor(Color(white: 0.67))
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(white: 0.16)))
            }.padding(.top, 10)
            Text("We'll remind you once a day until your Instagram is linked.")
                .font(.system(size: 11)).foregroundColor(Color(white: 0.4)).frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 6)
        }
    }

    private func scan() async {
        guard ScrubService.parseHandle(igInput) != nil else {
            scrubError = "That doesn't look like an Instagram handle. Use @name or your profile link."
            return
        }
        scrubbing = true; scrubError = nil
        let r = await ScrubService.shared.linkInstagramAndBuildTaste(handle: igInput)
        scrubbing = false
        if r.ok { scrubbed = true }
        else { scrubError = r.error ?? "Couldn't read that profile. Check the handle (it must be public) and try again." }
    }

    // MARK: Step 4 — first dump

    private var finishStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Make your first dump")
            sub("A dump is a set of photos you post together. Let Dumpster group your \(poolCount) photos for you, or start an empty one and pick them yourself.")

            Button { finish(true) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").font(.system(size: 14))
                    Text("Group them for me").font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(Color(hex: "#C8A96E"))
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(Color(hex: "#C8A96E").opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#C8A96E").opacity(0.45)))
            }
            .disabled(finishing).padding(.bottom, 10)

            primary("I'll pick them myself", enabled: !finishing, busy: finishing) { finish(false) }
        }
    }

    private func finish(_ useAI: Bool) {
        finishing = true
        onFinish(useAI)
    }
}
