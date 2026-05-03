import SwiftUI
import WebKit

// MARK: - App State (Observable)

/// Centralized app state shared between native views and the web bridge.
/// Updated to use LLMService instead of CaptionService for multi-provider support.
final class AppState: ObservableObject {
    @Published var webView: WKWebView?
    @Published var showAISuggest = false
    @Published var showSettings = false
    @Published var showFileCabinet = false  // NEW: File Cabinet menu
    @Published var statusText: String = "DUMPSTER"
    @Published var dumpCount: Int = 0
    @Published var isAnalyzing = false
    @Published var captionResults: [LLMService.CaptionResult] = []

    /// Send a status update that auto-clears after a delay.
    func showStatus(_ text: String, duration: TimeInterval = 3.0) {
        statusText = text
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.statusText = "DUMPSTER"
        }
    }

    /// Inject JavaScript into the web view with error handling.
    func evaluateJS(_ script: String, completion: ((Any?, Error?) -> Void)? = nil) {
        guard let webView else {
            completion?(nil, NSError(domain: "AppState", code: -1,
                                     userInfo: [NSLocalizedDescriptionKey: "WebView not available"]))
            return
        }
        webView.evaluateJavaScript(script, completionHandler: completion)
    }

    /// Send captions to the web app via the bridge.
    func sendCaptionsToWeb(_ results: [LLMService.CaptionResult]) {
        let payload = results.map { result -> [String: Any] in
            return [
                "dumpTitle": result.dumpTitle,
                "captions": result.captions,
                "vibe": result.vibe
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8) else { return }

        let escaped = jsonStr
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")

        let script = """
        if (window.__dumpsterBridge) {
            window.__dumpsterBridge.receiveCaptions('\(escaped)');
        }
        """
        evaluateJS(script)
    }
}

// MARK: - Root View

struct ContentView: View {
    @StateObject private var appState = AppState()

    // Dynamic Island animation state
    @State private var isExpanded = false

    // Haptic Feedback
    private let impact = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        ZStack(alignment: .top) {
            // 1. THE WEB CONTENT (Base Layer)
            DumpsterWebView(appState: appState)
                .ignoresSafeArea(.all)

            // 2. THE DYNAMIC ISLAND (Top) — sits over the hardware notch/DI cutout
            dynamicIslandView
                .frame(maxWidth: .infinity)
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

            // 3. AI SUGGESTIONS (Bottom Sheet)
            if appState.showAISuggest {
                CabinetMenuView(
                    isPresented: $appState.showAISuggest,
                    appState: appState
                )
                .zIndex(10)
                .transition(.move(edge: .bottom))
            }

            // 4. FILE CABINET MENU (Full Screen Overlay)
            if appState.showFileCabinet {
                FileCabinetMenuView(
                    isPresented: $appState.showFileCabinet,
                    appState: appState
                )
                .zIndex(20)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $appState.showSettings) {
            SettingsView(isPresented: $appState.showSettings)
        }
        // Default state: collapsed black pill that blends with the hardware Dynamic Island.
        // Tap to expand with status + credit badge + menu.
    }

    // MARK: - Dynamic Island

    private var dynamicIslandView: some View {
        ZStack {
            Capsule()
                .fill(Color.black)
                .frame(width: isExpanded ? 340 : 126, height: 37)

            // Status content inside the expanded capsule
            if isExpanded {
                HStack(spacing: 8) {
                    if appState.isAnalyzing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "#C8A96E")))
                            .scaleEffect(0.6)
                    }

                    Text(appState.statusText)
                        .font(.system(size: 11, weight: .bold))
                        .tracking(2)
                        .foregroundColor(Color(hex: "#C8A96E"))
                        .lineLimit(1)

                    if appState.dumpCount > 0 && !appState.isAnalyzing {
                        Text("\u{00B7}")
                            .foregroundColor(Color(hex: "#C8A96E").opacity(0.4))
                        Text("\(appState.dumpCount) dumps")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(hex: "#C8A96E").opacity(0.6))
                    }

                    Spacer()

                    // Credit badge — tappable, opens paywall
                    CreditBadge()

                    // Menu button
                    Button {
                        impact.impactOccurred()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            appState.showFileCabinet = true
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(hex: "#C8A96E").opacity(0.5))
                    }
                }
                .padding(.horizontal, 14)
                .transition(.opacity)
            }
        }
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

// MARK: - WebView Wrapper

struct DumpsterWebView: UIViewRepresentable {
    @ObservedObject var appState: AppState

    func makeCoordinator() -> Coordinator { Coordinator(appState: appState) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let userContentController = configuration.userContentController
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        configuration.setURLSchemeHandler(DumpsterSchemeHandler(), forURLScheme: "dumpster")

        let webFixScript = WKUserScript(
            source: """
            (function() {
                const style = document.createElement('style');
                style.innerHTML = `
                    .stray-question-mark, #stray-q, [class*="question-mark"] {
                        display: none !important;
                    }
                    .photo-caption-pill, [class*="pill-container"] {
                        transition: transform 0.5s cubic-bezier(0.175, 0.885, 0.32, 1.275) !important;
                    }
                `;
                document.head.appendChild(style);

                setTimeout(() => {
                    const pill = document.querySelector('.photo-caption-pill') || document.querySelector('[class*="pill-container"]');
                    if (pill) {
                        let startX = 0;
                        pill.addEventListener('touchstart', (e) => { startX = e.touches[0].clientX; }, { passive: true });
                        pill.addEventListener('touchend', (e) => {
                            const endX = e.changedTouches[0].clientX;
                            if (Math.abs(startX - endX) > 40) { pill.click(); }
                        });
                    }
                }, 1000);

                window.__dumpsterBridge = window.__dumpsterBridge || {};

                window.__dumpsterBridge.receiveCaptions = function(jsonStr) {
                    try {
                        const captions = JSON.parse(jsonStr);
                        console.log('[Dumpster] Received captions from native:', captions);
                        window.dispatchEvent(new CustomEvent('dumpster-captions', { detail: captions }));
                    } catch(e) {
                        console.error('[Dumpster] Failed to parse captions:', e);
                    }
                };

                window.__dumpsterBridge.receiveStatus = function(status) {
                    console.log('[Dumpster] Status:', status);
                    window.dispatchEvent(new CustomEvent('dumpster-status', { detail: status }));
                };

                setTimeout(() => {
                    if (window.webkit && window.webkit.messageHandlers.dumpsterBridge) {
                        window.webkit.messageHandlers.dumpsterBridge.postMessage({ type: 'bridgeReady' });
                    }
                }, 500);
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(webFixScript)
        userContentController.add(context.coordinator, name: "dumpsterBridge")
        userContentController.add(context.coordinator, name: "openSettings")
        configuration.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.allowsBackForwardNavigationGestures = false

        if let url = URL(string: "dumpster://app/index.html") {
            webView.load(URLRequest(url: url))
        }

        DispatchQueue.main.async {
            self.appState.webView = webView
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let appState: AppState

        init(appState: AppState) {
            self.appState = appState
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            switch message.name {
            case "openSettings":
                // Open the File Cabinet instead of the old settings
                DispatchQueue.main.async {
                    self.appState.showFileCabinet = true
                }

            case "dumpsterBridge":
                handleBridgeMessage(message.body)

            default:
                break
            }
        }

        private func handleBridgeMessage(_ body: Any) {
            if let dict = body as? [String: Any], let type = dict["type"] as? String {
                switch type {
                case "openAISuggest":
                    DispatchQueue.main.async { self.appState.showAISuggest = true }

                case "openFileCabinet":
                    DispatchQueue.main.async { self.appState.showFileCabinet = true }

                case "bridgeReady":
                    print("[Dumpster] Web bridge is ready")
                    if !appState.captionResults.isEmpty {
                        appState.sendCaptionsToWeb(appState.captionResults)
                    }

                case "dumpCount":
                    if let count = dict["count"] as? Int {
                        DispatchQueue.main.async { self.appState.dumpCount = count }
                    }

                case "requestCaptions":
                    DispatchQueue.main.async { self.appState.showAISuggest = true }

                default:
                    print("[Dumpster] Unknown bridge message type: \(type)")
                }
            } else {
                DispatchQueue.main.async { self.appState.showAISuggest = true }
            }
        }

        // MARK: - Navigation Delegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("""
                (function() {
                    try {
                        const data = localStorage.getItem('dumpster-dumps');
                        if (data) {
                            const dumps = JSON.parse(data);
                            return Array.isArray(dumps) ? dumps.length : 0;
                        }
                    } catch(e) {}
                    return 0;
                })();
            """) { [weak self] result, _ in
                if let count = result as? Int {
                    DispatchQueue.main.async {
                        self?.appState.dumpCount = count
                    }
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url {
                if url.scheme == "dumpster" {
                    decisionHandler(.allow)
                } else if url.scheme == "https" || url.scheme == "http" {
                    UIApplication.shared.open(url)
                    decisionHandler(.cancel)
                } else {
                    decisionHandler(.allow)
                }
            } else {
                decisionHandler(.allow)
            }
        }
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
