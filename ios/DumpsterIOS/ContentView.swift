import SwiftUI

// MARK: - App State (Observable)

/// Centralized app state shared across native views.
@MainActor
final class AppState: ObservableObject {

    // ── Overlay toggles ──
    @Published var showAISuggest = false
    @Published var showSettings = false
    @Published var showFileCabinet = false
    @Published var fileCabinetInitialTab: Int? = nil

    // ── Dynamic Island ──
    @Published var statusText: String = "DUMPSTER"
    @Published var dumpCount: Int = 0
    @Published var isAnalyzing = false

    // ── AI results ──
    @Published var captionResults: [LLMService.CaptionResult] = []

    // ── Onboarding ──
    @Published var showOnboarding: Bool = false

    // ── Native UI state ──
    @Published var activeDumpId: String?
    // ColorMode is defined in Models/AppEnums.swift (cases: dark, day, system)
    @Published var colorMode: ColorMode = .dark {
        didSet { UserDefaults.standard.set(colorMode.rawValue, forKey: "dumpster_colorMode") }
    }
    // PoolSize is defined in Models/AppEnums.swift (cases: small, medium, large)
    @Published var poolSize: PoolSize = .medium {
        didSet { UserDefaults.standard.set(poolSize.rawValue, forKey: "dumpster_poolSize") }
    }
    @Published var activeFilters: Set<FilterType> = []
    @Published var poolSearchQuery: String = ""
    @Published var lightboxPhotoId: String?
    @Published var addingToDumpId: String?
    @Published var activePoolTab: PoolTab = .photos

    // ── Accent color ──
    @Published var accentColorName: String = "gold" {
        didSet { UserDefaults.standard.set(accentColorName, forKey: "dumpster_accentColor") }
    }

    var accentColor: Color {
        switch accentColorName {
        case "silver":   return Color(hex: "#B0B0B0")
        case "rose":     return Color(hex: "#C8787E")
        case "emerald":  return Color(hex: "#6EC8A0")
        case "sapphire": return Color(hex: "#6E8EC8")
        case "lavender": return Color(hex: "#A06EC8")
        default:         return Color(hex: "#C8A96E") // gold
        }
    }

    // ── Pool scroll trigger ──
    @Published var scrollToPool: UUID? = nil

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
        if let ac = UserDefaults.standard.string(forKey: "dumpster_accentColor") {
            accentColorName = ac
        }
    }

    // MARK: - Status helper

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

    @State private var isExpanded = false
    @AppStorage("dumpster_onboardingDone") private var onboardingDone = false
    private let impact = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        ZStack(alignment: .top) {
            MainAppView()
                .environmentObject(appState)
                .environmentObject(undoManager)

            dynamicIslandView
                .padding(.top, isExpanded ? 0 : 11)
                .ignoresSafeArea(.all)
                .animation(.spring(response: 0.55, dampingFraction: 0.82), value: isExpanded)
                .onTapGesture {
                    impact.impactOccurred()
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                        isExpanded.toggle()
                    }
                }
                .onLongPressGesture(minimumDuration: 0.5) {
                    impact.impactOccurred()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        appState.showFileCabinet = true
                    }
                }

            if appState.showFileCabinet {
                FileCabinetMenuView(
                    isPresented: $appState.showFileCabinet,
                    appState: appState
                )
                .zIndex(20)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            if appState.lightboxPhotoId != nil {
                LightboxView()
                    .environmentObject(appState)
                    .zIndex(30)
            }

            if appState.showOnboarding {
                SpotlightTutorialView(isPresented: $appState.showOnboarding)
                    .zIndex(40)
                    .transition(.opacity)
            }
        }
        .background(Color.black)
        .onAppear {
            isExpanded = true
            if !onboardingDone { appState.showOnboarding = true }
        }
        .fullScreenCover(isPresented: $appState.showSettings) {
            SettingsView(isPresented: $appState.showSettings)
        }
        .fullScreenCover(isPresented: $appState.showAISuggest) {
            AISuggestView(isPresented: $appState.showAISuggest, appState: appState)
        }
        .onChange(of: appState.showOnboarding) { _, showing in
            if !showing { onboardingDone = true }
        }
    }

    private var dynamicIslandView: some View {
        let screenW = UIScreen.main.bounds.width
        let pillW: CGFloat = isExpanded ? screenW : 126
        let pillH: CGFloat = isExpanded ? 54 : 37
        return Capsule()
            .fill(Color.black)
            .frame(width: pillW, height: pillH)
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
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
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
