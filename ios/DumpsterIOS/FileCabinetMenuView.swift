import SwiftUI

// MARK: - File Cabinet Menu View

/// A full-screen overlay menu styled as a modern file cabinet with tab folders.
/// Each tab sticks out and can be tapped to open that section.
/// Dark theme with gold accent (#C8A96E), smooth animations.

struct FileCabinetMenuView: View {
    @Binding var isPresented: Bool
    @ObservedObject var appState: AppState
    @StateObject private var llmService = LLMService.shared

    @State private var selectedTab: CabinetTab? = nil
    @State private var appearAnimation = false
    @State private var tabsVisible = false

    private let gold = Color(hex: "#C8A96E")
    private let darkBg = Color(hex: "#0A0A0A")
    private let cardBg = Color(hex: "#141414")
    private let subtleBorder = Color.white.opacity(0.08)

    enum CabinetTab: Int, CaseIterable, Identifiable {
        case aiSettings = 0
        case myDumps = 1
        case photoPool = 2
        case appearance = 3
        case aboutHelp = 4

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .aiSettings: return "AI SETTINGS"
            case .myDumps:    return "MY DUMPS"
            case .photoPool:  return "PHOTO POOL"
            case .appearance: return "APPEARANCE"
            case .aboutHelp:  return "ABOUT / HELP"
            }
        }

        var icon: String {
            switch self {
            case .aiSettings: return "brain.head.profile"
            case .myDumps:    return "tray.full"
            case .photoPool:  return "photo.on.rectangle.angled"
            case .appearance: return "paintbrush"
            case .aboutHelp:  return "questionmark.circle"
            }
        }

        var tabColor: Color {
            switch self {
            case .aiSettings: return Color(hex: "#C8A96E")
            case .myDumps:    return Color(hex: "#A8C8A0")
            case .photoPool:  return Color(hex: "#A0B8C8")
            case .appearance: return Color(hex: "#C8A0C0")
            case .aboutHelp:  return Color(hex: "#C8B8A0")
            }
        }
    }

    var body: some View {
        ZStack {
            // Dimmed backdrop
            Color.black.opacity(appearAnimation ? 0.85 : 0.0)
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
        }
    }

    // MARK: - Cabinet View

    private var cabinetView: some View {
        VStack(spacing: 0) {
            // Header
            cabinetHeader

            // File Cabinet Body
            VStack(spacing: 0) {
                ForEach(Array(CabinetTab.allCases.enumerated()), id: \.element.id) { index, tab in
                    tabFolder(tab: tab, index: index)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Spacer()

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
                    .foregroundColor(.white.opacity(0.15))
            }
            .padding(.bottom, 40)
        }
    }

    private var cabinetHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("FILE CABINET")
                    .font(.system(size: 22, weight: .black))
                    .tracking(4)
                    .foregroundColor(.white)
                Text("Tap a folder to open")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.3))
            }

            Spacer()

            Button {
                dismissMenu()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 70)
        .padding(.bottom, 20)
    }

    // MARK: - Tab Folder

    private func tabFolder(tab: CabinetTab, index: Int) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
                    // Spacer to offset each tab
                    Spacer()
                        .frame(width: CGFloat(index) * 52 + 16)

                    // The tab itself
                    VStack(spacing: 0) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 10, weight: .semibold))
                            Text(tab.title)
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1.5)
                        }
                        .foregroundColor(darkBg)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 8,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 8
                            )
                            .fill(tab.tabColor)
                        )
                    }
                    .offset(y: -26)

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
                                .foregroundColor(.white.opacity(0.8))
                            Text(tabSubtitle(for: tab))
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.3))
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.2))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .frame(height: 80)
            .padding(.top, 20) // Space for the tab
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

    private func tabSubtitle(for tab: CabinetTab) -> String {
        switch tab {
        case .aiSettings:
            if let provider = llmService.preferredProvider() {
                return "\(provider.displayName) active"
            }
            return "No API keys configured"
        case .myDumps:
            return "\(appState.dumpCount) dumps saved"
        case .photoPool:
            return "Upload & label settings"
        case .appearance:
            return "Theme & colors"
        case .aboutHelp:
            return "Version 1.0.0"
        }
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
                        case .aiSettings:
                            AISettingsTabView(llmService: llmService)
                        case .myDumps:
                            MyDumpsTabView(appState: appState)
                        case .photoPool:
                            PhotoPoolTabView()
                        case .appearance:
                            AppearanceTabView()
                        case .aboutHelp:
                            AboutHelpTabView(llmService: llmService)
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
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                    Text("CABINET")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                }
                .foregroundColor(gold)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(gold.opacity(0.12))
                )
            }

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(tab.tabColor)
                Text(tab.title)
                    .font(.system(size: 13, weight: .black))
                    .tracking(2)
                    .foregroundColor(.white)
            }

            Spacer()

            // Invisible spacer for centering
            Color.clear.frame(width: 90, height: 1)
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
    @ObservedObject var llmService: LLMService
    @State private var expandedProvider: LLMService.LLMProvider? = nil
    @State private var apiKeyInputs: [LLMService.LLMProvider: String] = [:]
    @State private var keyVisibility: [LLMService.LLMProvider: Bool] = [:]
    @State private var savedConfirmation: LLMService.LLMProvider? = nil

    private let gold = Color(hex: "#C8A96E")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Active Provider Status
            activeProviderBanner

            // API Key Cards
            CabinetSectionHeader("API PROVIDERS", icon: "key")

            ForEach(LLMService.LLMProvider.allCases) { provider in
                apiKeyCard(for: provider)
            }

            // Labeling Sensitivity
            CabinetSectionHeader("LABELING SENSITIVITY", icon: "slider.horizontal.3")
            labelingSensitivityControl

            // Caption Style
            CabinetSectionHeader("CAPTION STYLE", icon: "text.quote")
            captionStylePicker

            // Intelligence Level
            CabinetSectionHeader("AUTO-DUMP INTELLIGENCE", icon: "brain")
            intelligenceLevelPicker
        }
        .onAppear {
            // Load current API keys into inputs
            for provider in LLMService.LLMProvider.allCases {
                apiKeyInputs[provider] = llmService.apiKey(for: provider)
                keyVisibility[provider] = false
            }
        }
    }

    // MARK: - Active Provider Banner

    private var activeProviderBanner: some View {
        HStack(spacing: 12) {
            if let provider = llmService.preferredProvider() {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Active: \(provider.displayName)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Text("Model: \(llmService.selectedModel(for: provider))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
            } else {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No AI Provider Active")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Text("Add an API key below to enable AI features")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
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
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            hasKey ? gold.opacity(0.2) : Color.white.opacity(0.06),
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
                    .foregroundColor(hasKey ? gold : .white.opacity(0.3))
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Text(hasKey ? "Key configured" : "Not configured")
                        .font(.system(size: 11))
                        .foregroundColor(hasKey ? .green.opacity(0.7) : .white.opacity(0.3))
                }

                Spacer()

                if hasKey {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                }

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))
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
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )

                        Button {
                            keyVisibility[provider] = !(keyVisibility[provider] ?? false)
                        } label: {
                            Image(systemName: keyVisibility[provider] == true ? "eye.slash" : "eye")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.4))
                                .frame(width: 40, height: 40)
                                .background(Color.white.opacity(0.05))
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
                            .foregroundColor(.white.opacity(0.25))

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
                                            .foregroundColor(isSelected ? .black : .white.opacity(0.5))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(
                                                isSelected
                                                    ? gold
                                                    : Color.white.opacity(0.05)
                                            )
                                            .cornerRadius(8)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(
                                                        isSelected ? gold : Color.white.opacity(0.08),
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
                    .foregroundColor(.white.opacity(0.3))
                Spacer()
                Text(String(format: "%.0f%%", llmService.labelingSensitivity * 100))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(gold)
                Spacer()
                Text("Strict")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
            }

            Slider(value: Binding(
                get: { llmService.labelingSensitivity },
                set: { llmService.labelingSensitivity = $0 }
            ), in: 0...1, step: 0.05)
            .tint(gold)

            Text("Controls the confidence threshold for AI photo auto-labeling. Higher values require more confidence before applying a label.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.25))
                .lineSpacing(3)
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
                                .foregroundColor(isSelected ? .black : .white.opacity(0.5))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(isSelected ? gold : Color.white.opacity(0.05))
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(
                                            isSelected ? gold : Color.white.opacity(0.08),
                                            lineWidth: 1
                                        )
                                )
                        }
                    }
                }
            }

            Text(llmService.captionStyle.promptModifier)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.25))
                .lineSpacing(3)
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
                            .foregroundColor(isSelected ? gold : .white.opacity(0.2))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(level.rawValue)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                            Text(level.description)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.35))
                        }

                        Spacer()
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isSelected ? gold.opacity(0.08) : Color.white.opacity(0.03))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(
                                        isSelected ? gold.opacity(0.3) : Color.white.opacity(0.06),
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
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
        .padding(.horizontal, 24)
    }
}

// MARK: - ═══════════════════════════════════════════
// MARK: Tab 2 — My Dumps
// MARK: - ═══════════════════════════════════════════

struct MyDumpsTabView: View {
    @ObservedObject var appState: AppState

    private let gold = Color(hex: "#C8A96E")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Stats Banner
            HStack(spacing: 20) {
                statBox(value: "\(appState.dumpCount)", label: "DUMPS")
                statBox(value: "—", label: "PHOTOS")
                statBox(value: "—", label: "SHARED")
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            // Dump List
            CabinetSectionHeader("SAVED DUMPS", icon: "tray.full")

            if appState.dumpCount == 0 {
                emptyDumpsView
            } else {
                dumpListPlaceholder
            }

            // Export Options
            CabinetSectionHeader("EXPORT", icon: "square.and.arrow.up")
            exportOptions

            // Dump History
            CabinetSectionHeader("HISTORY", icon: "clock.arrow.circlepath")
            historySection
        }
    }

    private func statBox(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .black))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private var emptyDumpsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(gold.opacity(0.3))
            Text("No dumps yet")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white.opacity(0.5))
            Text("Use the AI Builder to create your first dump")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
    }

    private var dumpListPlaceholder: some View {
        VStack(spacing: 8) {
            ForEach(0..<min(appState.dumpCount, 5), id: \.self) { index in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.15))
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Dump \(index + 1)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white.opacity(0.7))
                        Text("Tap to view in carousel")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.3))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.15))
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                )
            }
        }
        .padding(.horizontal, 24)
    }

    private var exportOptions: some View {
        VStack(spacing: 8) {
            exportButton(icon: "square.and.arrow.up", title: "Export All Dumps", subtitle: "Save as JSON backup")
            exportButton(icon: "photo.stack", title: "Export Photos", subtitle: "Save original photos to camera roll")
            exportButton(icon: "doc.text", title: "Export Captions", subtitle: "Copy all captions to clipboard")
        }
        .padding(.horizontal, 24)
    }

    private func exportButton(icon: String, title: String, subtitle: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(gold.opacity(0.6))
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.3))
                }

                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var historySection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "clock")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.2))
                Text("Dump history will appear here as you create and share dumps.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.3))
                    .lineSpacing(3)
                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - ═══════════════════════════════════════════
// MARK: Tab 3 — Photo Pool
// MARK: - ═══════════════════════════════════════════

struct PhotoPoolTabView: View {
    @State private var hujiSensitivity: Double = 0.7
    private let gold = Color(hex: "#C8A96E")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Upload Settings
            CabinetSectionHeader("UPLOAD SETTINGS", icon: "arrow.up.circle")

            VStack(alignment: .leading, spacing: 14) {
                settingToggle(title: "Auto-Analyze on Import", subtitle: "Run Vision AI when photos are added", isOn: true)
                settingToggle(title: "Preserve EXIF Data", subtitle: "Keep location and camera metadata", isOn: true)
                settingToggle(title: "Smart Thumbnails", subtitle: "Generate optimized preview images", isOn: true)
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

            // Huji Detection
            CabinetSectionHeader("HUJI DETECTION", icon: "camera.filters")

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Detection Sensitivity")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                    Text(String(format: "%.0f%%", hujiSensitivity * 100))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(gold)
                }

                Slider(value: $hujiSensitivity, in: 0...1, step: 0.05)
                    .tint(gold)

                Text("Adjusts how aggressively the app detects Huji-style film photos for special grouping.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.25))
                    .lineSpacing(3)
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

    private func settingToggle(title: String, subtitle: String, isOn: Bool) -> some View {
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
            // Static toggle representation (would be @State in production)
            RoundedRectangle(cornerRadius: 16)
                .fill(isOn ? gold.opacity(0.3) : Color.white.opacity(0.1))
                .frame(width: 44, height: 26)
                .overlay(
                    Circle()
                        .fill(isOn ? gold : Color.white.opacity(0.4))
                        .frame(width: 22, height: 22)
                        .offset(x: isOn ? 9 : -9)
                )
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
    @State private var selectedTheme: ThemeMode = .dark
    @State private var selectedAccent: AccentOption = .gold

    private let gold = Color(hex: "#C8A96E")

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
        case rose = "Rose"
        case emerald = "Emerald"
        case sapphire = "Sapphire"
        case lavender = "Lavender"

        var id: String { rawValue }

        var color: Color {
            switch self {
            case .gold:      return Color(hex: "#C8A96E")
            case .silver:    return Color(hex: "#B0B0B0")
            case .rose:      return Color(hex: "#C8787E")
            case .emerald:   return Color(hex: "#6EC8A0")
            case .sapphire:  return Color(hex: "#6E8EC8")
            case .lavender:  return Color(hex: "#A06EC8")
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Theme Selection
            CabinetSectionHeader("THEME MODE", icon: "circle.lefthalf.filled")

            HStack(spacing: 10) {
                ForEach(ThemeMode.allCases) { mode in
                    let isSelected = selectedTheme == mode
                    Button {
                        selectedTheme = mode
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
                                            isSelected ? gold : Color.white.opacity(0.1),
                                            lineWidth: isSelected ? 2 : 1
                                        )
                                )

                            Text(mode.rawValue)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(isSelected ? .white : .white.opacity(0.4))
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
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
                            selectedAccent = accent
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
                                    .foregroundColor(isSelected ? .white : .white.opacity(0.4))
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
                        .foregroundColor(.white.opacity(0.25))
                    Spacer()
                }

                HStack(spacing: 12) {
                    Capsule()
                        .fill(selectedAccent.color)
                        .frame(height: 36)
                        .overlay(
                            Text("DUMPSTER")
                                .font(.system(size: 11, weight: .bold))
                                .tracking(2)
                                .foregroundColor(.black)
                        )

                    Circle()
                        .fill(selectedAccent.color.opacity(0.15))
                        .frame(width: 36, height: 36)
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
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
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
// MARK: Tab 5 — About / Help
// MARK: - ═══════════════════════════════════════════

struct AboutHelpTabView: View {
    @ObservedObject var llmService: LLMService

    private let gold = Color(hex: "#C8A96E")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // App Info
            VStack(spacing: 16) {
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(gold)

                Text("DUMPSTER")
                    .font(.system(size: 20, weight: .black))
                    .tracking(6)
                    .foregroundColor(.white)

                Text("Photo Carousel Curation Tool")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)

            // Version Info
            CabinetSectionHeader("VERSION INFO", icon: "info.circle")

            VStack(spacing: 0) {
                infoRow("Version", value: "1.0.0")
                Divider().background(Color.white.opacity(0.06))
                infoRow("Build", value: "2025.05")
                Divider().background(Color.white.opacity(0.06))
                infoRow("Vision AI", value: "VNClassifyImageRequest")
                Divider().background(Color.white.opacity(0.06))
                infoRow("AI Provider", value: llmService.preferredProvider()?.displayName ?? "None")
                Divider().background(Color.white.opacity(0.06))
                infoRow("Active Model", value: {
                    if let p = llmService.preferredProvider() {
                        return llmService.selectedModel(for: p)
                    }
                    return "Local fallback"
                }())
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 24)

            // Connected Providers
            CabinetSectionHeader("CONNECTED PROVIDERS", icon: "link")

            VStack(spacing: 6) {
                ForEach(LLMService.LLMProvider.allCases) { provider in
                    HStack(spacing: 10) {
                        Image(systemName: provider.iconName)
                            .font(.system(size: 12))
                            .foregroundColor(llmService.hasAPIKey(for: provider) ? gold : .white.opacity(0.2))
                            .frame(width: 24)

                        Text(provider.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))

                        Spacer()

                        if llmService.hasAPIKey(for: provider) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 5, height: 5)
                                Text("Connected")
                                    .font(.system(size: 10))
                                    .foregroundColor(.green.opacity(0.7))
                            }
                        } else {
                            Text("Not connected")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.2))
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                }
            }
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 24)

            // Help
            CabinetSectionHeader("HELP", icon: "questionmark.circle")

            VStack(spacing: 8) {
                helpRow(icon: "sparkles", title: "How AI Suggest Works",
                        text: "Select photos, Vision AI classifies them, then your chosen LLM generates captions and titles.")
                helpRow(icon: "key", title: "API Keys",
                        text: "Keys are stored locally on your device in UserDefaults. For production, migrate to Keychain.")
                helpRow(icon: "arrow.triangle.2.circlepath", title: "Multi-Provider Support",
                        text: "Add keys for multiple providers. Dumpster uses the first available provider in priority order: OpenAI, Claude, Gemini, Manus, Perplexity.")
            }
            .padding(.horizontal, 24)

            // Production Note
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 12))
                        .foregroundColor(.yellow.opacity(0.7))
                    Text("PRODUCTION NOTE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundColor(.yellow.opacity(0.7))
                }
                Text("For production, migrate API key storage to iOS Keychain and consider using a server-side proxy to avoid embedding keys in the app.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.3))
                    .lineSpacing(4)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.yellow.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.yellow.opacity(0.12), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 24)
            .padding(.top, 24)

            // Cache
            CabinetSectionHeader("STORAGE", icon: "internaldrive")

            Button {
                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("dumpster_ai")
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
                            .foregroundColor(.white.opacity(0.7))
                        Text("Remove temporary analysis files")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    Spacer()
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
        }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))
            Spacer()
            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func helpRow(icon: String, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(gold.opacity(0.5))
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
            }
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.3))
                .lineSpacing(3)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}
