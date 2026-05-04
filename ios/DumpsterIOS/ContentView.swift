import SwiftUI

// MARK: - App State (Observable)

/// Centralized app state shared across native views.
/// Phase 6: removed all WKWebView / JS-bridge fields.
@MainActor
final class AppState: ObservableObject {

    // ── Overlay toggles ──
    @Published var showAISuggest = false
    @Published var showSettings = false
    @Published var showFileCabinet = false

    // ── Dynamic Island ──
    @Published var statusText: String = "DUMPSTER"
    @Published var dumpCount: Int = 0
    @Published var isAnalyzing = false

    // ── AI results ──
    @Published var captionResults: [LLMService.CaptionResult] = []

    // ── Native UI state (used by views built in Phases 4–6) ──
    @Published var activeDumpId: String?
    @Published var colorMode: ColorMode = .dark {
        didSet { UserDefaults.standard.set(colorMode.rawValue, forKey: "dumpster_colorMode") }
    }
    @Published var poolSize: PoolSize = .medium {
        didSet { UserDefaults.standard.set(poolSize.rawValue, forKey: "dumpster_poolSize") }
    }
    @Published var activeFilters: Set<FilterType> = []
    @Published var poolSearchQuery: String = ""
    @Published var lightboxPhotoId: String?
    @Published var addingToDumpId: String?
    @Published var activePoolTab: PoolTab = .photos

    // MARK: - Init

    init() {
        if let cm = UserDefaults.standard.string(forKey: "dumpster_colorMode"),
           let mode = ColorMode(rawValue: cm) {
            colorMode = mode
        }
        if let ps = UserDefaults.standard.string(forKey: "dumpster_poolSize"),
           let size = PoolSize(rawValue: ps) {
            poolSize = size
        }
    }

    // MARK: - Status helper

    /// Show a transient status in the Dynamic Island, then revert to "DUMPSTER".
    /// If a newer status comes in before the timer fires, the older revert is skipped.
    func showStatus(_ text: String, duration: TimeInterval = 3.0) {
        statusText = text
        let captured = text
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            if self.statusText == captured { self.statusText = "DUMPSTER" }
        }
    }

}

// MARK: - Root View

struct ContentView: View {
    @StateObject private var appState = AppState()
    @StateObject private var undoManager = DumpsterUndoManager()

    // Dynamic Island animation state
    @State private var isExpanded = true

    // Haptic Feedback
    private let impact = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        ZStack(alignment: .top) {
            // 1. NATIVE CONTENT (replaces DumpsterWebView)
            MainAppView()
                .environmentObject(appState)
                .environmentObject(undoManager)

            // 2. THE DYNAMIC ISLAND (Top) — sits over the hardware notch/DI cutout
            dynamicIslandView
                .padding(.top, 11)
                .ignoresSafeArea(.all)
                .animation(.easeInOut(duration: 2.5), value: isExpanded)
                .onTapGesture {
                    impact.impactOccurred()
                    withAnimation(.interpolatingSpring(stiffness: 120, damping: 12)) {
                        isExpanded.toggle()
                    }
                }
                .onLongPressGesture(minimumDuration: 0.5) {
                    // Long press on Dynamic Island opens File Cabinet
                    impact.impactOccurred()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        appState.showFileCabinet = true
                    }
                }

            // 3. AI DUMP BUILDER — full-screen photo picker + clustering
            // showAISuggest is toggled by the AUTO-GENERATE button in MainAppView.
            // AISuggestView handles its own PhotosPicker; API key is optional
            // (falls back to local caption generation automatically).

            // 4. FILE CABINET MENU (Full Screen Overlay)
            if appState.showFileCabinet {
                FileCabinetMenuView(
                    isPresented: $appState.showFileCabinet,
                    appState: appState
                )
                .zIndex(20)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // 5. LIGHTBOX (full-screen photo overlay — Phase 5)
            if appState.lightboxPhotoId != nil {
                LightboxView()
                    .environmentObject(appState)
                    .zIndex(30)
            }
        }
        .background(Color.black)
        .fullScreenCover(isPresented: $appState.showSettings) {
            SettingsView(isPresented: $appState.showSettings)
        }
        .fullScreenCover(isPresented: $appState.showAISuggest) {
            AISuggestView(isPresented: $appState.showAISuggest, appState: appState)
        }
        // Default state: collapsed black pill that blends with the hardware Dynamic Island.
        // Tap to expand with status + credit badge + menu.
    }

    // MARK: - Dynamic Island

    private var dynamicIslandView: some View {
        let pillW: CGFloat = isExpanded ? 230 : 126
        let pillH: CGFloat = 37

        return ZStack {
            // Background capsule
            Capsule()
                .fill(Color.black)

            // Content — only shown when expanded
            if isExpanded {
                HStack(spacing: 8) {
                    if appState.isAnalyzing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "#C8A96E")))
                            .scaleEffect(0.55)
                            .frame(width: 14, height: 14)
                    }

                    Text(appState.statusText)
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.6)
                        .foregroundColor(Color(hex: "#C8A96E"))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)

                    Button {
                        impact.impactOccurred()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            appState.showFileCabinet = true
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(hex: "#C8A96E").opacity(0.7))
                    }
                }
                .padding(.horizontal, 14)
                // Constrained to pill width so nothing escapes the capsule
                .frame(width: pillW, height: pillH)
                .transition(.opacity)
            }
        }
        // Single source of truth for pill size — applies to both capsule and content
        .frame(width: pillW, height: pillH)
        .clipShape(Capsule())
    }
}

// MARK: - File Cabinet Menu Component (AI Suggestions — Connected to Real Data)

struct CabinetMenuView: View {
    @Binding var isPresented: Bool
    @ObservedObject var appState: AppState
    @ObservedObject private var llmService = LLMService.shared
    @State private var dragOffset: CGFloat = 0
    @State private var selectedCaptionIndex: [String: Int] = [:]
    @State private var copiedCaption: String?

    private let gold = Color(red: 200/255, green: 169/255, blue: 110/255)

    var body: some View {
        ZStack(alignment: .bottom) {
            // Dimmed backdrop
            Color.black.opacity(dragOffset > 0 ? 0.4 - (dragOffset / 1000) : 0.4)
                .ignoresSafeArea(.all)
                .onTapGesture {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isPresented = false
                    }
                }

            // Background shadow card
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color(white: 0.15))
                .frame(height: 700)
                .offset(y: 60 + (dragOffset * 0.5))
                .scaleEffect(0.92)
                .shadow(radius: 10)

            // Main content card
            VStack(spacing: 0) {
                // Drag handle
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 40, height: 5)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                // Header
                HStack {
                    Text("AI SUGGESTIONS")
                        .font(.system(size: 13, weight: .black))
                        .tracking(2)
                        .foregroundColor(gold)
                    Spacer()

                    // Show active provider
                    if let provider = llmService.activeProvider {
                        HStack(spacing: 4) {
                            Image(systemName: provider.iconName)
                                .font(.system(size: 10))
                            Text(provider.displayName)
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1)
                        }
                        .foregroundColor(gold.opacity(0.5))
                    }

                    if llmService.isGenerating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: gold))
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "sparkles")
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)

                Divider().background(Color.white.opacity(0.1))

                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if appState.captionResults.isEmpty && !llmService.isGenerating {
                            emptyStateView
                        } else if llmService.isGenerating {
                            generatingView
                        } else {
                            captionResultsView
                        }
                    }
                    .padding(24)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 750)
            .background(Color(hex: "#121212"))
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .offset(y: dragOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.height > 0 {
                            dragOffset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if value.translation.height > 150 || value.velocity.height > 500 {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                isPresented = false
                            }
                        } else {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                dragOffset = 0
                            }
                        }
                    }
            )
        }
        .ignoresSafeArea(.all, edges: .bottom)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.bubble")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(gold.opacity(0.4))
                .padding(.top, 40)

            Text("No captions yet")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white.opacity(0.6))

            Text("Use the AI Builder to select photos.\nVision AI will group them and generate captions.")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.3))
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .padding(.horizontal, 16)

            if !llmService.hasAnyAPIKey {
                HStack(spacing: 8) {
                    Image(systemName: "key")
                        .font(.system(size: 12))
                        .foregroundColor(.yellow.opacity(0.7))
                    Text("Add an API key in the File Cabinet menu for AI captions")
                        .font(.system(size: 12))
                        .foregroundColor(.yellow.opacity(0.6))
                }
                .padding(12)
                .background(Color.yellow.opacity(0.06))
                .cornerRadius(10)
                .padding(.top, 8)
            } else if let provider = llmService.preferredProvider() {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("\(provider.displayName) ready")
                        .font(.system(size: 12))
                        .foregroundColor(.green.opacity(0.6))
                }
                .padding(12)
                .background(Color.green.opacity(0.06))
                .cornerRadius(10)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Generating State

    private var generatingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: gold))
                .scaleEffect(1.2)
                .padding(.top, 40)

            Text("Generating captions...")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.6))

            if let provider = llmService.activeProvider {
                Text("Using \(provider.displayName) to craft the perfect captions")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Caption Results

    private var captionResultsView: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(appState.captionResults) { result in
                captionCard(for: result)
            }
        }
    }

    private func captionCard(for result: LLMService.CaptionResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            captionCardHeader(result: result)
            captionCardOptions(result: result)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func captionCardHeader(result: LLMService.CaptionResult) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(result.dumpTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Text(result.vibe.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundColor(gold.opacity(0.6))
            }
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 12))
                .foregroundColor(gold.opacity(0.4))
        }
    }

    private func captionCardOptions(result: LLMService.CaptionResult) -> some View {
        ForEach(Array(result.captions.enumerated()), id: \.offset) { index, caption in
            CaptionOptionButton(
                caption: caption,
                isSelected: selectedCaptionIndex[result.dumpTitle] == index,
                isCopied: copiedCaption == caption,
                gold: gold,
                onTap: {
                    selectedCaptionIndex[result.dumpTitle] = index
                    UIPasteboard.general.string = caption
                    copiedCaption = caption
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if copiedCaption == caption { copiedCaption = nil }
                    }
                }
            )
        }
    }
}

// MARK: - Caption Option Button (Extracted to fix compiler type-check)

struct CaptionOptionButton: View {
    let caption: String
    let isSelected: Bool
    let isCopied: Bool
    let gold: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                captionText
                Spacer()
                statusIcon
            }
            .padding(14)
            .background(backgroundShape)
            .overlay(borderShape)
        }
        .buttonStyle(.plain)
    }

    private var captionText: some View {
        Text(caption)
            .font(.system(size: 14))
            .foregroundColor(isSelected ? .white : .white.opacity(0.6))
            .multilineTextAlignment(.leading)
            .lineSpacing(3)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isCopied {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.green)
        } else {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.2))
        }
    }

    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(isSelected ? gold.opacity(0.1) : Color.white.opacity(0.04))
    }

    private var borderShape: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(isSelected ? gold.opacity(0.3) : Color.white.opacity(0.06), lineWidth: 1)
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
