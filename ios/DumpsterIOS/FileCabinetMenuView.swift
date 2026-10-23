import SwiftUI
import SwiftData

// MARK: - File Cabinet Menu View

/// A full-screen overlay menu styled as a modern file cabinet with tab folders.
/// Each tab sticks out and can be tapped to open that section.
/// Dark theme with gold accent (#C8A96E), smooth animations.

struct FileCabinetMenuView: View {
    @Binding var isPresented: Bool
    @ObservedObject var appState: AppState
    @StateObject private var llmService = LLMService.shared
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var credits = CreditManager.shared
    @ObservedObject private var subscription = SubscriptionManager.shared
    @Environment(\.colorScheme) private var cs
    @State private var showSignIn = false

    @State private var selectedTab: CabinetTab? = nil
    @State private var appearAnimation = false
    @State private var tabsVisible = false

    private let gold = Color(hex: "#C8A96E")
    // Always-dark, independent of theme — used for text sitting on a light pastel
    // tab-color pill (tab.tabColor), which needs a fixed dark foreground for contrast
    // in both Light and Dark mode.
    private let fixedDarkText = Color(hex: "#0A0A0A")
    // Theme-aware (were hardcoded dark-only constants — NATIVE_PORT.md §G).
    private var darkBg: Color { Theme.bg(appState.colorMode, cs) }
    private var cardBg: Color { Theme.bg2(appState.colorMode, cs) }
    private var subtleBorder: Color { Theme.border(appState.colorMode, cs) }
    private var primaryText: Color { Theme.text(appState.colorMode, cs) }
    private var secondaryText: Color { Theme.text2(appState.colorMode, cs) }
    private var tertiaryText: Color { Theme.text3(appState.colorMode, cs) }

    /// Same six folders, same order, same titles/subtitles as web's MainMenu.
    enum CabinetTab: Int, CaseIterable, Identifiable {
        case aiTools = 0
        case friends = 1
        case appearance = 2
        case aiKeys = 3
        case socialMedia = 4
        case aboutHelp = 5

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .aiTools:     return "AI TOOLS"
            case .friends:     return "FRIENDS"
            case .appearance:  return "APPEARANCE"
            case .aiKeys:      return "YOUR AI KEYS"
            case .socialMedia: return "SOCIAL MEDIA"
            case .aboutHelp:   return "ABOUT / HELP"
            }
        }

        var subtitle: String {
            switch self {
            case .aiTools:     return "Taste Profile · Instagram Scrub · Dump Styles"
            case .friends:     return "Find friends · Profiles · Comments"
            case .appearance:  return "Accent color"
            case .aiKeys:      return "Add & verify your own keys"
            case .socialMedia: return "Connect & export"
            case .aboutHelp:   return "Dumpster · Version 1.0"
            }
        }

        var icon: String {
            switch self {
            case .aiTools:     return "sparkles"
            case .friends:     return "person.2"
            case .appearance:  return "paintbrush"
            case .aiKeys:      return "key"
            case .socialMedia: return "square.and.arrow.up"
            case .aboutHelp:   return "info.circle"
            }
        }

        var tabColor: Color {
            switch self {
            case .aiTools:     return Color(hex: "#C8A96E")
            case .friends:     return Color(hex: "#A8C8A0")
            case .appearance:  return Color(hex: "#C8A0C0")
            case .aiKeys:      return Color(hex: "#A0B8C8")
            case .socialMedia: return Color(hex: "#C8A8A0")
            case .aboutHelp:   return Color(hex: "#C8B8A0")
            }
        }
    }

    var body: some View {
        ZStack {
            // Solid backdrop — fully opaque so content behind doesn't bleed through
            darkBg.opacity(appearAnimation ? 1.0 : 0.0)
                .ignoresSafeArea()
                .onTapGesture {
                    if selectedTab != nil {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            selectedTab = nil
                        }
                    } else {
                        dismissMenu()
                    }
                }

            if selectedTab == nil {
                // MARK: - Cabinet View (Tab Folders)
                cabinetView
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.95)),
                        removal: .opacity.combined(with: .scale(scale: 0.95))
                    ))
            } else {
                // MARK: - Open Folder View
                folderContentView
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                appearAnimation = true
            }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.15)) {
                tabsVisible = true
            }
            // Deep-link into a specific tab if requested
            if let rawTab = appState.fileCabinetInitialTab,
               let tab = CabinetTab(rawValue: rawTab) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        selectedTab = tab
                    }
                }
                appState.fileCabinetInitialTab = nil
            }
        }
    }

    // MARK: - Cabinet View

    private var cabinetView: some View {
        VStack(spacing: 0) {
            // Header
            cabinetHeader

            // File Cabinet Body
            ScrollView {
                VStack(spacing: 0) {
                    accountCard
                        .padding(.top, 8)

                    ForEach(Array(CabinetTab.allCases.enumerated()), id: \.element.id) { index, tab in
                        if tab == .aiTools {
                            tabFolder(tab: tab, index: index).tourAnchor(.cabinetAI)
                        } else {
                            tabFolder(tab: tab, index: index)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }

            Spacer(minLength: 0)

            // Bottom branding
            HStack(spacing: 6) {
                Image(systemName: "archivebox")
                    .font(.system(size: 10))
                    .foregroundColor(gold.opacity(0.3))
                Text("DUMPSTER")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(3)
                    .foregroundColor(gold.opacity(0.3))
                Text("v1.0")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(tertiaryText.opacity(0.5))
            }
            .padding(.bottom, 40)
        }
        .background(darkBg)
    }

    private var cabinetHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("MAIN MENU")
                    .font(.system(size: 22, weight: .black))
                    .tracking(4)
                    .foregroundColor(primaryText)
                Text("Tap a folder to open")
                    .font(.system(size: 12))
                    .foregroundColor(secondaryText)
            }

            Spacer()

            Button {
                dismissMenu()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(secondaryText)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(subtleBorder))
            }
            .tourAnchor(.cabinetClose)
        }
        .padding(.horizontal, 24)
        .padding(.top, 70)
        .padding(.bottom, 20)
    }

    // MARK: - Tab Folder

    private func tabFolder(tab: CabinetTab, index: Int) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if tab == .friends { openFriends(); return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                selectedTab = tab
            }
        } label: {
            ZStack(alignment: .topLeading) {
                // Folder body
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(cardBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(subtleBorder, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 8, y: 4)

                // Tab sticking out
                HStack(spacing: 0) {
                    // Spacer to offset each tab — tighter stagger so tabs don't run off screen
                    Spacer()
                        .frame(width: CGFloat(index) * 40 + 16)

                    // The tab itself
                    VStack(spacing: 0) {
                        // Web parity: gold, icon-only tab
                        Image(systemName: tab.icon)
                            .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(fixedDarkText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 7,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 7
                            )
                            .fill(gold)
                        )
                    }
                    .offset(y: -22)

                    Spacer()
                }

                // Folder content preview
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: .light))
                            .foregroundColor(tab.tabColor.opacity(0.6))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(tab.title)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(primaryText.opacity(0.8))
                            Text(tab.subtitle)
                                .font(.system(size: 11))
                                .foregroundColor(secondaryText)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(tertiaryText)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .frame(height: 72)
            .padding(.top, 24) // Space for the tab (must be >= tab offset of 22)
            .opacity(tabsVisible ? 1 : 0)
            .offset(y: tabsVisible ? 0 : 20)
            .animation(
                .spring(response: 0.5, dampingFraction: 0.8)
                    .delay(Double(index) * 0.08),
                value: tabsVisible
            )
        }
        .buttonStyle(FolderButtonStyle())
    }

    // MARK: - Folder Content View

    @ViewBuilder
    private var folderContentView: some View {
        if let tab = selectedTab {
            VStack(spacing: 0) {
                // Folder header with back button
                folderHeader(tab: tab)

                // Folder content
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        switch tab {
                        case .aiTools:
                            AISettingsTabView(mode: .tools, llmService: llmService, appState: appState)
                        case .friends:
                            EmptyView()   // opens the Friends sheet instead of a panel
                        case .appearance:
                            AppearanceTabView(appState: appState, onDone: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                    selectedTab = nil
                                }
                            })
                        case .aiKeys:
                            AISettingsTabView(mode: .keys, llmService: llmService, appState: appState)
                        case .socialMedia:
                            SocialMediaTabView(appState: appState)
                        case .aboutHelp:
                            AboutHelpTabView(appState: appState, onDismiss: { dismissMenu() })
                        }
                    }
                    .padding(.bottom, 60)
                }
            }
            .background(darkBg.ignoresSafeArea())
        }
    }

    private func folderHeader(tab: CabinetTab) -> some View {
        HStack(spacing: 12) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    selectedTab = nil
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(gold)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(gold.opacity(0.12)))
            }
            .tourAnchor(.cabinetBack)

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(tab.tabColor)
                Text(tab.title)
                    .font(.system(size: 13, weight: .black))
                    .tracking(2)
                    .foregroundColor(primaryText)
            }

            Spacer()

            // Invisible spacer for centering
            Color.clear.frame(width: 36, height: 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 64)
        .padding(.bottom, 16)
        .background(
            darkBg
                .overlay(
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [tab.tabColor.opacity(0.08), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .ignoresSafeArea()
        )
    }

    // MARK: - Account block (web: avatar initial, email, "FREE · N CREDITS" / PRO, Sign out; guest sign-in card)

    @ViewBuilder
    private var accountCard: some View {
        let accent = appState.accentColor
        if auth.isSignedIn {
            HStack(spacing: 12) {
                Text(String((auth.userEmail ?? "U").prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(.black)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(accent))
                VStack(alignment: .leading, spacing: 3) {
                    Text(auth.userEmail ?? "User")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(primaryText.opacity(0.85))
                        .lineLimit(1)
                    Text("\(subscription.isPro ? "PRO" : "FREE") · \(credits.balance) CREDITS")
                        .font(.system(size: 10))
                        .tracking(0.6)
                        .foregroundColor(accent)
                }
                Spacer()
                Button {
                    Task { await auth.signOut() }
                    dismissMenu()
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 14))
                        .foregroundColor(tertiaryText)
                        .padding(6)
                }
                .accessibilityLabel("Sign out")
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(cardBg)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(subtleBorder, lineWidth: 1))
            )
            .padding(.top, 8)
        } else {
            Button { showSignIn = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person")
                        .font(.system(size: 16))
                        .foregroundColor(accent)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(accent.opacity(0.15)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Sign In")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(accent)
                        Text("Save dumps · Get 15 free AI credits")
                            .font(.system(size: 10))
                            .foregroundColor(tertiaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(accent.opacity(0.4))
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(accent.opacity(0.2), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .sheet(isPresented: $showSignIn) {
                SignInView().presentationDetents([.large])
            }
        }
    }

    /// Web: closes the menu, then opens Connections (signed in) or the sign-in sheet.
    private func openFriends() {
        guard auth.isSignedIn else { showSignIn = true; return }
        dismissMenu()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            SocialStore.shared.openFriends = true
        }
    }

    // MARK: - Helpers

    private func dismissMenu() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            appearAnimation = false
            tabsVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isPresented = false
        }
    }
}

// MARK: - Folder Button Style

struct FolderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Section Header Helper

struct CabinetSectionHeader: View {
    let title: String
    let icon: String?
    let gold = Color(hex: "#C8A96E")

    init(_ title: String, icon: String? = nil) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(gold.opacity(0.5))
            }
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundColor(.white.opacity(0.3))
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 12)
    }
}

// MARK: - ═══════════════════════════════════════════
// MARK: Tab 1 — AI Settings
// MARK: - ═══════════════════════════════════════════

struct AISettingsTabView: View {
    /// Web has two separate folders: AI TOOLS (taste / rules / scrub / styles) and YOUR AI KEYS (keys only).
    enum Mode { case tools, keys }
    var mode: Mode = .tools
    @ObservedObject var llmService: LLMService
    @ObservedObject var appState: AppState
    @Environment(\.colorScheme) private var cs
    @State private var expandedProvider: LLMService.LLMProvider? = nil
    @State private var apiKeyInputs: [LLMService.LLMProvider: String] = [:]
    @State private var keyVisibility: [LLMService.LLMProvider: Bool] = [:]
    @State private var savedConfirmation: LLMService.LLMProvider? = nil
    @AppStorage("ai_style_profile") private var styleProfile = ""
    @AppStorage("ai_engagement_playbook") private var engagementPlaybook = ""
    @AppStorage("ai_rules") private var aiRules = ""
    /// ID of the SavedScrub currently driving `styleProfile`. Empty = manual / none.
    @AppStorage("active_scrub_id") private var activeScrubId = ""

    @State private var showScrubSheet = false
    @State private var showScrubPaywall = false
    @State private var reapplyingScrub: SavedScrub? = nil
    @Query(sort: \SavedScrub.createdAt, order: .reverse) private var savedScrubs: [SavedScrub]

    // AI Rules editor state
    @State private var draftRule: String = ""
    @State private var openRule: Int? = nil
    @FocusState private var newRuleFocused: Bool
    @State private var savedToast: Bool = false

    // Build from Instagram (free) — same box as web's Taste Profile card
    @State private var igHandleInput: String = UserDefaults.standard.string(forKey: "ig_handle") ?? ""
    @State private var igBuilding = false
    @State private var igBuildMsg: String? = nil

    private let gold = Color(hex: "#C8A96E")
    // Theme-aware chrome (NATIVE_PORT.md §G — was hardcoded dark-only white-alpha).
    private var primaryText: Color { Theme.text(appState.colorMode, cs) }
    private var secondaryText: Color { Theme.text2(appState.colorMode, cs) }
    private var tertiaryText: Color { Theme.text3(appState.colorMode, cs) }
    private var cardFill: Color { Theme.bg2(appState.colorMode, cs) }
    private var cardBorder: Color { Theme.border(appState.colorMode, cs) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if mode == .tools { toolsContent } else { keysContent }
        }
        .onAppear {
            // Load current API keys into inputs
            for provider in LLMService.LLMProvider.allCases {
                apiKeyInputs[provider] = llmService.apiKey(for: provider)
                keyVisibility[provider] = false
            }
        }
    }

    // MARK: - AI TOOLS folder (web order: Taste Profile + Build -> AI Rules -> Instagram Scrub -> Dump Styles)

    @ViewBuilder
    private var toolsContent: some View {
        sectionNote("Powered by Claude Haiku & Apify").padding(.top, 12)

        // AI Taste Profile — describes the user
        CabinetSectionHeader("AI TASTE PROFILE", icon: "person.text.rectangle")
        sectionNote("Who you are. Valet, captions and Auto Gen read this.")
        styleProfileCard
            .tourAnchor(.yourStyle)
            .padding(.horizontal, 24)

        // AI Rules (belongs with the profile)
        CabinetSectionHeader("AI RULES", icon: "list.bullet.rectangle")
        aiRulesCard
            .padding(.horizontal, 24)

        // Instagram Scrub — directly above Dump Styles
        CabinetSectionHeader("INSTAGRAM SCRUB", icon: "bookmark")
        sectionNote("Pull photos or a whole account's style from Instagram.")
        scrubLibraryCard
            .padding(.horizontal, 24)

        // Dump Styles — formed from scrubs
        CabinetSectionHeader("DUMP STYLES", icon: "square.stack.3d.up")
        sectionNote("Looks you borrowed from scrubs. Turn one on to apply it.")
        DumpStylesCard(appState: appState)
            .tourAnchor(.dumpStyles)
            .padding(.horizontal, 24)

        // iOS-only AI behaviour controls (not on web) — kept here after the web items.
        CabinetSectionHeader("LABELING SENSITIVITY", icon: "slider.horizontal.3")
        labelingSensitivityControl

        CabinetSectionHeader("CAPTION STYLE", icon: "text.quote")
        captionStylePicker

        CabinetSectionHeader("AUTO-DUMP INTELLIGENCE", icon: "brain")
        intelligenceLevelPicker
    }

    // MARK: - YOUR AI KEYS folder

    @ViewBuilder
    private var keysContent: some View {
        activeProviderBanner

        CabinetSectionHeader("YOUR OWN API KEY (OPTIONAL)", icon: "key")

        ForEach(LLMService.LLMProvider.allCases) { provider in
            apiKeyCard(for: provider)
        }
    }

    private func sectionNote(_ t: String) -> some View {
        Text(t).font(.system(size: 12)).foregroundColor(tertiaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.bottom, 6)
    }

    // MARK: - Active Provider Banner

    @State private var showPaywallFromAISettings = false

    // MARK: - AI Style Profile card

    @Environment(\.modelContext) private var modelContext

    private var styleProfileCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Describe your aesthetic. The AI uses this when generating dumps and captions.")
                .font(.system(size: 12))
                .foregroundColor(tertiaryText)
                .lineSpacing(3)

            styleProfileEditor

            HStack(spacing: 8) {
                Spacer()
                Text("\(styleProfile.count)/\(AIProfileLimits.tasteProfileMax)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(tertiaryText)
            }

            // Free: build the profile from YOUR public Instagram account
            HStack(spacing: 8) {
                TextField("Build from Instagram: @username (free)", text: $igHandleInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 12))
                    .foregroundColor(primaryText)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(cardFill))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardBorder, lineWidth: 1))
                Button { buildFromInstagram() } label: {
                    Text(igBuilding ? "Reading…" : "Build")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(gold))
                        .opacity(igHandleInput.trimmingCharacters(in: .whitespaces).isEmpty || igBuilding ? 0.5 : 1)
                }
                .buttonStyle(.plain)
                .disabled(igHandleInput.trimmingCharacters(in: .whitespaces).isEmpty || igBuilding)
            }
            if let m = igBuildMsg {
                Text(m).font(.system(size: 11)).foregroundColor(.red.opacity(0.85)).lineSpacing(2)
            }
        }
        .padding(16)
        .background(cardBackground)
        .sheet(isPresented: $showScrubSheet) {
            ScrubInstagramSheet(currentProfile: $styleProfile, activeScrubId: $activeScrubId)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $reapplyingScrub) { saved in
            ScrubInstagramSheet(currentProfile: $styleProfile, activeScrubId: $activeScrubId, preloadedScrub: saved)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showScrubPaywall) {
            PaywallView().presentationDetents([.large])
        }
    }

    private var styleProfileEditor: some View {
        TextEditor(text: $styleProfile)
            .font(.system(size: 13))
            .foregroundColor(primaryText)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 80, maxHeight: 120)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(cardFill))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(cardBorder, lineWidth: 1))
            .onChange(of: styleProfile) { _, newVal in
                if newVal.count > AIProfileLimits.tasteProfileMax {
                    styleProfile = String(newVal.prefix(AIProfileLimits.tasteProfileMax))
                    return
                }
                guard !activeScrubId.isEmpty else {
                    scheduleCloudSync()
                    return
                }
                if let active = savedScrubs.first(where: { $0.id == activeScrubId }),
                   active.styleDescription != newVal {
                    activeScrubId = ""
                }
                scheduleCloudSync()
            }
    }

    /// Push taste_profile / ai_rules / caption_pool to Supabase so edits made here
    /// survive across devices. `scheduleSave` no-ops without a signed-in session.
    private func scheduleCloudSync() {
        guard let userId = AuthManager.shared.userId, let jwt = AuthManager.shared.jwt else { return }
        AIProfileSync.shared.scheduleSave(userId: userId, jwt: jwt)
    }

    /// Free taste-profile build (same path onboarding uses). Taste Profile is about YOU, so a handle that
    /// isn't the linked account is pointed at Instagram Scrub (Dump Style) instead.
    private func buildFromInstagram() {
        guard let handle = ScrubService.parseHandle(igHandleInput) else {
            igBuildMsg = "That doesn't look like an Instagram handle. Enter it like @yourname."
            return
        }
        let linked = (UserDefaults.standard.string(forKey: "ig_handle") ?? "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "@/ ")).lowercased()
        if !linked.isEmpty && linked != handle.lowercased() {
            igBuildMsg = "Taste Profile is about YOU, and your linked Instagram is @\(linked). Use Instagram Scrub below to save @\(handle) as a Dump Style."
            return
        }
        igBuilding = true
        igBuildMsg = nil
        Task { @MainActor in
            let r = await ScrubService.shared.linkInstagramAndBuildTaste(handle: handle)
            igBuilding = false
            if r.ok { igHandleInput = ""; HapticManager.shared.playAdded() }
            else { igBuildMsg = r.error ?? "Couldn't read that profile." }
        }
    }

    private var generateFromInstagramButton: some View {
        Button {
            if SubscriptionManager.shared.isPro {
                showScrubSheet = true
            } else {
                showScrubPaywall = true
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: SubscriptionManager.shared.isPro ? "sparkles" : "lock.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("Scrub Instagram")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.8)
            }
            .foregroundColor(gold)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .overlay(Capsule().strokeBorder(gold.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .tourAnchor(.scrub)
    }

    private var scrubLibraryCard: some View {
        VStack(spacing: 8) {
            HStack { generateFromInstagramButton; Spacer() }
            if !savedScrubs.isEmpty {
                Text("Past scrubs — tap to re-apply without paying.")
                    .font(.system(size: 12))
                    .foregroundColor(tertiaryText)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ForEach(savedScrubs) { scrub in
                scrubLibraryRow(scrub)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(cardFill)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(cardBorder, lineWidth: 1)
            )
    }

    // MARK: - AI Rules (numbered list)

    /// Split the stored \n-separated string into rule strings, dropping empties.
    private var rulesList: [String] {
        aiRules.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func writeRules(_ rules: [String]) {
        aiRules = rules.joined(separator: "\n")
        flashSaved()
        scheduleCloudSync()
    }

    private func deleteRule(at index: Int) {
        var current = rulesList
        guard current.indices.contains(index) else { return }
        HapticManager.shared.playRemove()
        current.remove(at: index)
        openRule = nil
        writeRules(current)
    }

    private func addDraftRule() {
        let trimmed = draftRule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var current = rulesList
        current.append(trimmed)
        guard current.joined(separator: "\n").count <= AIProfileLimits.aiRulesMax else {
            HapticManager.shared.playRemove()   // full — web caps rules at AI_RULES_MAX
            return
        }
        writeRules(current)
        draftRule = ""
        HapticManager.shared.playAdded()
    }

    private func flashSaved() {
        withAnimation(.easeOut(duration: 0.2)) { savedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeIn(duration: 0.25)) { savedToast = false }
        }
    }

    private var aiRulesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rules the AI MUST follow when generating dumps and captions. Add one rule per line.")
                .font(.system(size: 12))
                .foregroundColor(tertiaryText)
                .lineSpacing(3)

            // Existing rules
            if rulesList.isEmpty {
                emptyRulesHint
            } else {
                // Tap-to-open chips (web parity): "Rule 1", "Rule 2"… show the rule text when tapped.
                FlowLayout(spacing: 6) {
                    ForEach(Array(rulesList.enumerated()), id: \.offset) { idx, _ in
                        Button { openRule = (openRule == idx) ? nil : idx } label: {
                            Text("Rule \(idx + 1)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(openRule == idx ? primaryText : secondaryText)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Capsule().fill(openRule == idx ? gold.opacity(0.18) : cardFill))
                                .overlay(Capsule().stroke(openRule == idx ? gold : cardBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(openRule == idx ? .isSelected : [])
                    }
                }
                if let idx = openRule, rulesList.indices.contains(idx) {
                    ruleRow(index: idx, text: rulesList[idx])
                }
            }

            // Add a rule
            HStack(spacing: 8) {
                TextField("Add a rule — e.g. \"no emojis\"", text: $draftRule)
                    .focused($newRuleFocused)
                    .font(.system(size: 13))
                    .foregroundColor(primaryText)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(cardFill))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(cardBorder, lineWidth: 1))
                    .submitLabel(.done)
                    .onSubmit { addDraftRule() }

                Button { addDraftRule() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(draftRule.isEmpty ? tertiaryText : .black)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(draftRule.isEmpty ? cardFill : gold))
                }
                .buttonStyle(.plain)
                .disabled(draftRule.isEmpty)
            }

            // Footer: count + saved indicator
            HStack {
                if savedToast {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("SAVED")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(1.2)
                    }
                    .foregroundColor(.green)
                    .transition(.opacity)
                }
                Spacer()
                Text("\(rulesList.count) RULE\(rulesList.count == 1 ? "" : "S") · \(aiRules.count)/\(AIProfileLimits.aiRulesMax)")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(1.2)
                    .foregroundColor(tertiaryText)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var emptyRulesHint: some View {
        VStack(spacing: 6) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 18, weight: .light))
                .foregroundColor(tertiaryText)
            Text("No rules yet — add your first rule below")
                .font(.system(size: 11))
                .foregroundColor(tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    private func ruleRow(index: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1).")
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundColor(gold)
                .frame(width: 22, alignment: .leading)

            Text(text)
                .font(.system(size: 13))
                .foregroundColor(primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Button { deleteRule(at: index) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(tertiaryText)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(cardBorder))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(cardFill))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardBorder, lineWidth: 1))
    }

    // MARK: - Scrub Library Row

    private func scrubLibraryRow(_ scrub: SavedScrub) -> some View {
        let isActive = activeScrubId == scrub.id

        return HStack(spacing: 12) {
            // Left badge: bookmark normally, green check when active
            ZStack {
                Circle()
                    .fill((isActive ? Color.green : gold).opacity(isActive ? 0.18 : 0.12))
                Image(systemName: isActive ? "checkmark" : "bookmark.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(isActive ? .green : gold)
            }
            .frame(width: 28, height: 28)

            // Tappable body — instant apply
            Button { applyScrub(scrub) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("@\(scrub.handle)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(primaryText)
                            .lineLimit(1)
                        if isActive {
                            Text("ACTIVE")
                                .font(.system(size: 8, weight: .heavy))
                                .tracking(0.8)
                                .foregroundColor(.green)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    Text("\(scrub.postsAnalyzed) posts · \(Self.relativeDate(scrub.createdAt))")
                        .font(.system(size: 10))
                        .foregroundColor(tertiaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Eye = view full report (preloads sheet, no network call)
            Button { reapplyingScrub = scrub } label: {
                Image(systemName: "eye")
                    .font(.system(size: 11))
                    .foregroundColor(tertiaryText)
                    .padding(6)
            }
            .buttonStyle(.plain)

            // Trash = delete
            Button { deleteScrub(scrub) } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(tertiaryText)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isActive ? Color.green.opacity(0.06) : cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isActive ? Color.green.opacity(0.35) : cardBorder, lineWidth: 1)
        )
    }

    /// Tap-row-to-apply: replace the style profile + engagement playbook, mark this scrub as active.
    /// Mirrors ScrubInstagramSheet.replaceProfile (750-char caps).
    private func applyScrub(_ scrub: SavedScrub) {
        guard activeScrubId != scrub.id else {
            // Already active — small haptic so the tap still feels acknowledged.
            HapticManager.shared.playTick()
            return
        }
        HapticManager.shared.playSuccess()
        styleProfile = String(scrub.styleDescription.prefix(AIProfileLimits.tasteProfileMax))
        engagementPlaybook = String(scrub.engagementPlaybook.prefix(750))
        activeScrubId = scrub.id
    }

    private func deleteScrub(_ scrub: SavedScrub) {
        HapticManager.shared.playRemove()
        // If we're deleting the active one, clear the active marker (textbox stays
        // as-is so the user doesn't lose what they're working with).
        if activeScrubId == scrub.id {
            activeScrubId = ""
        }
        modelContext.delete(scrub)
        try? modelContext.save()
    }

    private static func relativeDate(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }

    private var proGateCard: some View {
        Button { showPaywallFromAISettings = true } label: {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("PRO FEATURE")
                        .font(.system(size: 10, weight: .black))
                        .tracking(1.6)
                }
                .foregroundColor(gold)

                Text("Bring Your Own AI Keys")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(primaryText)

                Text("Subscribe to DUMPSTER Pro to plug in your own OpenAI, Claude, Gemini, Manus, or Perplexity keys for unlimited captions and full control.")
                    .font(.system(size: 12))
                    .foregroundColor(secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 8)

                HStack(spacing: 6) {
                    Text("UNLOCK PRO")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.4)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(gold)
                .clipShape(Capsule())
                .shadow(color: gold.opacity(0.30), radius: 8, x: 0, y: 3)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(gold.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(gold.opacity(0.20), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 24)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPaywallFromAISettings) {
            PaywallView()
                .presentationDetents([.large])
        }
    }

    private var activeProviderBanner: some View {
        HStack(spacing: 12) {
            if let provider = llmService.preferredProvider() {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Active: \(provider.displayName)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(primaryText)
                    Text("Model: \(llmService.selectedModel(for: provider))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(tertiaryText)
                }
            } else {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No AI Provider Active")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(primaryText)
                    Text("Add an API key below to enable AI features")
                        .font(.system(size: 11))
                        .foregroundColor(tertiaryText)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(cardBorder, lineWidth: 1)
                )
        )
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    // MARK: - API Key Card

    private func apiKeyCard(for provider: LLMService.LLMProvider) -> some View {
        let isExpanded = expandedProvider == provider
        let hasKey = llmService.hasAPIKey(for: provider)

        return VStack(alignment: .leading, spacing: 0) {
            apiKeyCardHeader(provider: provider, isExpanded: isExpanded, hasKey: hasKey)
            if isExpanded {
                apiKeyCardExpanded(provider: provider)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            hasKey ? gold.opacity(0.2) : cardBorder,
                            lineWidth: 1
                        )
                )
        )
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    private func apiKeyCardHeader(provider: LLMService.LLMProvider, isExpanded: Bool, hasKey: Bool) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                expandedProvider = isExpanded ? nil : provider
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: provider.iconName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(hasKey ? gold : tertiaryText)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(primaryText)
                    Text(hasKey ? "Key configured" : "Not configured")
                        .font(.system(size: 11))
                        .foregroundColor(hasKey ? .green.opacity(0.7) : tertiaryText)
                }

                Spacer()

                if hasKey {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                }

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(tertiaryText)
            }
            .padding(16)
        }
        .buttonStyle(.plain)
    }

    private func apiKeyCardExpanded(provider: LLMService.LLMProvider) -> some View {
        let isSaved = savedConfirmation == provider
        return VStack(alignment: .leading, spacing: 14) {
                    // API Key Input
                    HStack(spacing: 10) {
                        Group {
                            if keyVisibility[provider] == true {
                                TextField(provider.keyPlaceholder, text: binding(for: provider))
                            } else {
                                SecureField(provider.keyPlaceholder, text: binding(for: provider))
                            }
                        }
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(primaryText)
                        .padding(12)
                        .background(cardFill)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(cardBorder, lineWidth: 1)
                        )

                        Button {
                            keyVisibility[provider] = !(keyVisibility[provider] ?? false)
                        } label: {
                            Image(systemName: keyVisibility[provider] == true ? "eye.slash" : "eye")
                                .font(.system(size: 13))
                                .foregroundColor(tertiaryText)
                                .frame(width: 40, height: 40)
                                .background(cardFill)
                                .cornerRadius(10)
                        }
                    }

                    // Save / Clear buttons
                    HStack(spacing: 10) {
                        Button {
                            let key = apiKeyInputs[provider] ?? ""
                            llmService.setAPIKey(key, for: provider)
                            savedConfirmation = provider
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                if savedConfirmation == provider {
                                    savedConfirmation = nil
                                }
                            }
                        } label: {
                            Text(isSaved ? "SAVED" : "SAVE KEY")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1.5)
                                .foregroundColor(.black)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(isSaved ? Color.green : gold)
                                .cornerRadius(8)
                        }

                        if !(apiKeyInputs[provider] ?? "").isEmpty {
                            Button {
                                apiKeyInputs[provider] = ""
                                llmService.setAPIKey("", for: provider)
                            } label: {
                                Text("CLEAR")
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(1)
                                    .foregroundColor(.red.opacity(0.7))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(Color.red.opacity(0.08))
                                    .cornerRadius(8)
                            }
                        }

                        Spacer()
                    }

                    // Model Selection
                    VStack(alignment: .leading, spacing: 6) {
                        Text("MODEL")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.5)
                            .foregroundColor(tertiaryText)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(provider.availableModels, id: \.self) { model in
                                    let isSelected = llmService.selectedModel(for: provider) == model
                                    Button {
                                        llmService.setSelectedModel(model, for: provider)
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    } label: {
                                        Text(model)
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .foregroundColor(isSelected ? .black : secondaryText)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(
                                                isSelected
                                                    ? gold
                                                    : cardFill
                                            )
                                            .cornerRadius(8)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(
                                                        isSelected ? gold : cardBorder,
                                                        lineWidth: 1
                                                    )
                                            )
                                    }
                                }
                            }
                        }
                    }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func binding(for provider: LLMService.LLMProvider) -> Binding<String> {
        Binding(
            get: { apiKeyInputs[provider] ?? "" },
            set: { apiKeyInputs[provider] = $0 }
        )
    }

    // MARK: - Labeling Sensitivity

    private var labelingSensitivityControl: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Permissive")
                    .font(.system(size: 10))
                    .foregroundColor(tertiaryText)
                Spacer()
                Text(String(format: "%.0f%%", llmService.labelingSensitivity * 100))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(gold)
                Spacer()
                Text("Strict")
                    .font(.system(size: 10))
                    .foregroundColor(tertiaryText)
            }

            Slider(value: Binding(
                get: { llmService.labelingSensitivity },
                set: { llmService.labelingSensitivity = $0 }
            ), in: 0...1, step: 0.05)
            .tint(gold)

            Text("Controls the confidence threshold for AI photo auto-labeling. Higher values require more confidence before applying a label.")
                .font(.system(size: 11))
                .foregroundColor(tertiaryText)
                .lineSpacing(3)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(cardBorder, lineWidth: 1)
                )
        )
        .padding(.horizontal, 24)
    }

    // MARK: - Caption Style

    private var captionStylePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LLMService.CaptionStyle.allCases) { style in
                        let isSelected = llmService.captionStyle == style
                        Button {
                            llmService.captionStyle = style
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Text(style.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(isSelected ? .black : secondaryText)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(isSelected ? gold : cardFill)
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(
                                            isSelected ? gold : cardBorder,
                                            lineWidth: 1
                                        )
                                )
                        }
                    }
                }
            }

            Text(llmService.captionStyle.promptModifier)
                .font(.system(size: 11))
                .foregroundColor(tertiaryText)
                .lineSpacing(3)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(cardBorder, lineWidth: 1)
                )
        )
        .padding(.horizontal, 24)
    }

    // MARK: - Intelligence Level

    private var intelligenceLevelPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(LLMService.IntelligenceLevel.allCases) { level in
                let isSelected = llmService.intelligenceLevel == level
                Button {
                    llmService.intelligenceLevel = level
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16))
                            .foregroundColor(isSelected ? gold : tertiaryText)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(level.rawValue)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(primaryText)
                            Text(level.description)
                                .font(.system(size: 11))
                                .foregroundColor(tertiaryText)
                        }

                        Spacer()
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isSelected ? gold.opacity(0.08) : cardFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(
                                        isSelected ? gold.opacity(0.3) : cardBorder,
                                        lineWidth: 1
                                    )
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(cardBorder, lineWidth: 1)
                )
        )
        .padding(.horizontal, 24)
    }
}

// MARK: - ═══════════════════════════════════════════
// MARK: Folder 5 — Social Media ("Connect & export")
// MARK: - ═══════════════════════════════════════════

struct SocialMediaTabView: View {
    @ObservedObject var appState: AppState
    @Environment(\.colorScheme) private var cs

    private var accent: Color { appState.accentColor }
    private var primaryText: Color { Theme.text(appState.colorMode, cs) }
    private var secondaryText: Color { Theme.text2(appState.colorMode, cs) }
    private var tertiaryText: Color { Theme.text3(appState.colorMode, cs) }
    private var cardFill: Color { Theme.bg2(appState.colorMode, cs) }
    private var cardBorder: Color { Theme.border(appState.colorMode, cs) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Same three platforms, order and copy as web (all "SOON" there too).
            CabinetSectionHeader("CONNECT YOUR ACCOUNTS", icon: "link")
            VStack(spacing: 12) {
                platformRow(name: "Instagram", icon: "camera", color: Color(hex: "#E1306C"),
                            desc: "Export carousels directly to Instagram")
                platformRow(name: "TikTok", icon: "play.rectangle", color: primaryText,
                            desc: "Share photo dumps as TikTok slideshows")
                platformRow(name: "Twitter / X", icon: "bubble.left.and.bubble.right", color: Color(hex: "#999999"),
                            desc: "Post carousel threads to X")
            }
            .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 6) {
                Text("COMING IN V1.1")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundColor(accent)
                Text("Connect your social accounts to export carousels directly. Schedule posts, manage captions, and track engagement.")
                    .font(.system(size: 11))
                    .foregroundColor(tertiaryText)
                    .lineSpacing(3)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(accent.opacity(0.12), lineWidth: 1))
            )
            .padding(.horizontal, 24)
            .padding(.top, 16)

            // iOS-only: relocated from the removed MY DUMPS tab.
            CabinetSectionHeader("EXPORT", icon: "square.and.arrow.up")
            VStack(spacing: 8) {
                exportButton(icon: "square.and.arrow.up", title: "Export All Dumps", subtitle: "Save as JSON backup")
                exportButton(icon: "photo.stack", title: "Export Photos", subtitle: "Save original photos to camera roll")
                exportButton(icon: "doc.text", title: "Export Captions", subtitle: "Copy all captions to clipboard")
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 4)
    }

    private func platformRow(name: String, icon: String, color: Color, desc: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.1)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.25), lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 14, weight: .bold)).foregroundColor(primaryText)
                Text(desc).font(.system(size: 11)).foregroundColor(tertiaryText)
            }
            Spacer()
            Text("SOON")
                .font(.system(size: 9, weight: .bold))
                .tracking(1)
                .foregroundColor(tertiaryText)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(cardBorder.opacity(0.5)))
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardFill)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(cardBorder, lineWidth: 1))
        )
    }

    private func exportButton(icon: String, title: String, subtitle: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(accent.opacity(0.6))
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .bold)).foregroundColor(secondaryText)
                    Text(subtitle).font(.system(size: 11)).foregroundColor(tertiaryText)
                }
                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(cardFill)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(cardBorder, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Library stats (relocated from MY DUMPS; lives in ABOUT / HELP)

struct LibraryStatsRow: View {
    @Query private var dumps: [PhotoDump]
    @Environment(\.colorScheme) private var cs
    @ObservedObject var appState: AppState

    // "Photos in use" = distinct photos assigned to at least one dump.
    private var photosInUse: Int { Set(dumps.flatMap { $0.photoIDs }).count }

    var body: some View {
        HStack(spacing: 20) {
            statBox(value: "\(dumps.count)", label: "DUMPS")
            statBox(value: "\(photosInUse)", label: "PHOTOS IN USE")
        }
        .padding(.horizontal, 24)
    }

    private func statBox(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .black))
                .foregroundColor(Theme.text(appState.colorMode, cs))
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(1.5)
                .foregroundColor(Theme.text3(appState.colorMode, cs))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.bg2(appState.colorMode, cs))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border(appState.colorMode, cs), lineWidth: 1))
        )
    }
}

// MARK: - ═══════════════════════════════════════════
// MARK: Photo import settings (relocated from the removed PHOTO POOL tab; lives in ABOUT / HELP)
// MARK: - ═══════════════════════════════════════════

struct ImportSettingsSection: View {
    @AppStorage("pool_autoAnalyze") private var autoAnalyze = true
    @AppStorage("pool_preserveExif") private var preserveExif = true
    @AppStorage("pool_smartThumbnails") private var smartThumbnails = true
    @AppStorage("custom_labels") private var customLabelsJSON = "[]"
    @State private var newLabelText = ""

    private let gold = Color(hex: "#C8A96E")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            VStack(alignment: .leading, spacing: 14) {
                settingToggle(title: "Auto-Analyze on Import", subtitle: "Run Vision AI when photos are added", isOn: $autoAnalyze)
                settingToggle(title: "Preserve EXIF Data", subtitle: "Keep location and camera metadata", isOn: $preserveExif)
                settingToggle(title: "Smart Thumbnails", subtitle: "Generate optimized preview images", isOn: $smartThumbnails)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 24)

            // Label Management
            CabinetSectionHeader("LABEL MANAGEMENT", icon: "tag")

            VStack(alignment: .leading, spacing: 12) {
                Text("Auto-generated labels from Vision AI")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.35))

                let categories = ["AUTOMOTIVE", "PORTRAIT", "NIGHTLIFE", "DINING", "TRAVEL",
                                  "FITNESS", "ARCHITECTURE", "ART", "FASHION", "STUDIO"]
                FlowLayout(spacing: 8) {
                    ForEach(categories, id: \.self) { category in
                        Text(category)
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1)
                            .foregroundColor(gold.opacity(0.7))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(gold.opacity(0.1))
                            )
                            .overlay(
                                Capsule().stroke(gold.opacity(0.2), lineWidth: 1)
                            )
                    }
                }

                // Custom labels
                let customLabels = parseCustomLabels()
                if !customLabels.isEmpty {
                    Text("CUSTOM LABELS")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.5)
                        .foregroundColor(.white.opacity(0.25))
                        .padding(.top, 4)

                    FlowLayout(spacing: 8) {
                        ForEach(customLabels, id: \.self) { label in
                            HStack(spacing: 4) {
                                Text(label.uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(1)
                                    .foregroundColor(.white.opacity(0.7))
                                Button {
                                    removeCustomLabel(label)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(Color.white.opacity(0.08))
                            )
                            .overlay(
                                Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                        }
                    }
                }

                // Add new label
                HStack(spacing: 8) {
                    TextField("New label...", text: $newLabelText)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )

                    Button {
                        addCustomLabel()
                    } label: {
                        Text("Add")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(gold)
                            .cornerRadius(8)
                    }
                    .disabled(newLabelText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 24)
        }
    }

    private func settingToggle(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.3))
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(gold)
        }
    }

    private func parseCustomLabels() -> [String] {
        guard let data = customLabelsJSON.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return arr
    }

    private func addCustomLabel() {
        let trimmed = newLabelText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var labels = parseCustomLabels()
        labels.append(trimmed)
        if let data = try? JSONEncoder().encode(labels),
           let json = String(data: data, encoding: .utf8) {
            customLabelsJSON = json
        }
        newLabelText = ""
    }

    private func removeCustomLabel(_ label: String) {
        var labels = parseCustomLabels()
        labels.removeAll { $0 == label }
        if let data = try? JSONEncoder().encode(labels),
           let json = String(data: data, encoding: .utf8) {
            customLabelsJSON = json
        }
    }
}

// MARK: - Flow Layout Helper

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalHeight = currentY + lineHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}

// MARK: - ═══════════════════════════════════════════
// MARK: Tab 4 — Appearance
// MARK: - ═══════════════════════════════════════════

struct AppearanceTabView: View {
    @ObservedObject var appState: AppState
    var onDone: (() -> Void)? = nil
    @Environment(\.colorScheme) private var cs

    private let gold = Color(hex: "#C8A96E")
    // Theme-aware chrome (NATIVE_PORT.md §G) — the Light/Dark preview swatches inside
    // each mode's tile intentionally stay fixed white/dark, since they're literal
    // previews of what that mode looks like, not screen chrome.
    private var primaryText: Color { Theme.text(appState.colorMode, cs) }
    private var secondaryText: Color { Theme.text2(appState.colorMode, cs) }
    private var tertiaryText: Color { Theme.text3(appState.colorMode, cs) }
    private var cardFill: Color { Theme.bg2(appState.colorMode, cs) }
    private var cardBorder: Color { Theme.border(appState.colorMode, cs) }

    private var selectedTheme: ThemeMode {
        switch appState.colorMode {
        case .day:    return .light
        case .dark:   return .dark
        case .system: return .system
        }
    }

    private var selectedAccent: AccentOption {
        AccentOption(rawValue: appState.accentColorName.capitalized) ?? .gold
    }

    enum ThemeMode: String, CaseIterable, Identifiable {
        case light = "Light"
        case dark = "Dark"
        case system = "System"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .light:  return "sun.max"
            case .dark:   return "moon"
            case .system: return "gear"
            }
        }
    }

    enum AccentOption: String, CaseIterable, Identifiable {
        case gold = "Gold"
        case silver = "Silver"
        case grey = "Grey"
        case rose = "Rose"
        case emerald = "Emerald"
        case sapphire = "Sapphire"
        case lavender = "Lavender"

        var id: String { rawValue }

        var color: Color {
            switch self {
            case .gold:      return Color(hex: "#C8A96E")
            case .silver:    return Color(hex: "#B0B0B0")
            case .grey:      return Color(hex: "#7A7A7A")
            case .rose:      return Color(hex: "#C8787E")
            case .emerald:   return Color(hex: "#6EC8A0")
            case .sapphire:  return Color(hex: "#6E8EC8")
            case .lavender:  return Color(hex: "#A06EC8")
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Accent Color
            CabinetSectionHeader("ACCENT COLOR", icon: "paintpalette")

            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 10) {
                    ForEach(AccentOption.allCases) { accent in
                        let isSelected = selectedAccent == accent
                        Button {
                            appState.accentColorName = accent.rawValue.lowercased()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            VStack(spacing: 8) {
                                Circle()
                                    .fill(accent.color)
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: isSelected ? 2 : 0)
                                    )
                                    .shadow(color: accent.color.opacity(isSelected ? 0.5 : 0), radius: 8)

                                Text(accent.rawValue)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(isSelected ? primaryText : tertiaryText)
                            }
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isSelected ? accent.color.opacity(0.1) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Preview
                HStack(spacing: 12) {
                    Text("PREVIEW")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.5)
                        .foregroundColor(tertiaryText)
                    Spacer()
                }

                HStack(spacing: 12) {
                    Button {
                        // Color is already saved on tap of the swatch — this just confirms + pops back
                        onDone?()
                    } label: {
                        Capsule()
                            .fill(selectedAccent.color)
                            .frame(height: 44)
                            .overlay(
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .black))
                                    Text("DUMPSTER")
                                        .font(.system(size: 11, weight: .bold))
                                        .tracking(2)
                                }
                                .foregroundColor(.black)
                            )
                            .shadow(color: selectedAccent.color.opacity(0.30), radius: 10, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)

                    Circle()
                        .fill(selectedAccent.color.opacity(0.15))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "sparkles")
                                .font(.system(size: 14))
                                .foregroundColor(selectedAccent.color)
                        )
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(cardBorder, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 24)

            // Theme Selection
            CabinetSectionHeader("THEME MODE", icon: "circle.lefthalf.filled")

            HStack(spacing: 10) {
                ForEach(ThemeMode.allCases) { mode in
                    let isSelected = selectedTheme == mode
                    Button {
                        switch mode {
                        case .light:  appState.colorMode = .day
                        case .dark:   appState.colorMode = .dark
                        case .system: appState.colorMode = .system
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        VStack(spacing: 10) {
                            // Theme preview
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    mode == .light
                                        ? Color.white
                                        : mode == .dark
                                            ? Color(hex: "#1A1A1A")
                                            : LinearGradient(
                                                colors: [Color.white, Color(hex: "#1A1A1A")],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                              ).asColor
                                )
                                .frame(height: 60)
                                .overlay(
                                    VStack(spacing: 4) {
                                        Image(systemName: mode.icon)
                                            .font(.system(size: 16))
                                            .foregroundColor(
                                                mode == .light ? .black.opacity(0.6) : .white.opacity(0.6)
                                            )
                                    }
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(
                                            isSelected ? gold : cardBorder,
                                            lineWidth: isSelected ? 2 : 1
                                        )
                                )

                            Text(mode.rawValue)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(isSelected ? primaryText : tertiaryText)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(cardBorder, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 24)
        }
    }
}

// Helper to convert LinearGradient to a Color-like view
extension LinearGradient {
    var asColor: Color { Color.gray }
}

// MARK: - ═══════════════════════════════════════════
// MARK: Folder 6 — About / Help (web parity + iOS-only device settings)
// MARK: - ═══════════════════════════════════════════

struct AboutHelpTabView: View {
    @ObservedObject var appState: AppState
    var onDismiss: () -> Void = {}
    @Environment(\.colorScheme) private var cs

    private var accent: Color { appState.accentColor }
    private var primaryText: Color { Theme.text(appState.colorMode, cs) }
    private var secondaryText: Color { Theme.text2(appState.colorMode, cs) }
    private var tertiaryText: Color { Theme.text3(appState.colorMode, cs) }
    private var cardFill: Color { Theme.bg2(appState.colorMode, cs) }
    private var cardBorder: Color { Theme.border(appState.colorMode, cs) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Same rows, same order as web's About panel.
            VStack(spacing: 0) {
                infoRow("App", value: "Dumpster")
                Divider().background(cardBorder)
                infoRow("Version", value: "1.0.0")
                Divider().background(cardBorder)
                infoRow("Platform", value: "iOS")
                Divider().background(cardBorder)
                infoRow("AI Model", value: "Claude Haiku Vision")
                Divider().background(cardBorder)
                infoRow("Made by", value: "Lee Scott")
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(cardFill)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(cardBorder, lineWidth: 1))
            )
            .padding(.horizontal, 24)
            .padding(.top, 16)

            // Replay the tour
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                appState.showOnboarding = true
                onDismiss()
            } label: {
                Text("REPLAY THE TOUR")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(accent.opacity(0.1))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(accent.opacity(0.25), lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.top, 20)

            // Legal links (same three as web)
            HStack(spacing: 16) {
                if let u = URL(string: "\(ReferralManager.webBase)/privacy") { Link("Privacy", destination: u) }
                if let u = URL(string: "\(ReferralManager.webBase)/terms") { Link("Terms", destination: u) }
                Spacer()
                if let u = URL(string: "mailto:axiomonellc@outlook.com") { Link("Contact", destination: u) }
            }
            .font(.system(size: 11))
            .tracking(0.4)
            .foregroundColor(secondaryText)
            .padding(.horizontal, 24)
            .padding(.top, 20)

            // ── iOS-only (not on web): relocated from the removed MY DUMPS / PHOTO POOL tabs ──
            CabinetSectionHeader("YOUR LIBRARY", icon: "tray.full")
            LibraryStatsRow(appState: appState)

            CabinetSectionHeader("PHOTO IMPORT", icon: "arrow.up.circle")
            ImportSettingsSection()

            CabinetSectionHeader("STORAGE", icon: "internaldrive")
            Button {
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("dumpster_ai")
                try? FileManager.default.removeItem(at: tempDir)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundColor(.red.opacity(0.6))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clear AI Cache")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(secondaryText)
                        Text("Remove temporary analysis files")
                            .font(.system(size: 11))
                            .foregroundColor(tertiaryText)
                    }
                    Spacer()
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(cardFill)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(cardBorder, lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
        }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .tracking(0.5)
                .foregroundColor(tertiaryText)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(primaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
