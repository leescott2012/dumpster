import SwiftUI

// MARK: - Targets + anchor plumbing
//
// Mirror of client/src/components/GuidedTour.tsx — keep step order and copy identical.
// Real controls are tagged with `.tourAnchor(.x)`; the overlay reads their frames
// through an anchor preference, dims everything else, and waits for the real tap.

enum TourTarget: String {
    case menuButton, cabinetAI, scrub, dumpStyles, cabinetBack, cabinetClose
    case dumpMenu, photoCard, photoDots, autoGen, newDump, pool, friends, yourStyle, credits
}

struct TourAnchorKey: PreferenceKey {
    static var defaultValue: [TourTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TourTarget: Anchor<CGRect>], nextValue: () -> [TourTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { first, _ in first }
    }
}

extension Notification.Name {
    static let tourTapped = Notification.Name("dumpster.tourTapped")
}

extension View {
    /// Tags a real control for the tour and reports taps on it (without blocking them).
    func tourAnchor(_ target: TourTarget) -> some View {
        self
            .anchorPreference(key: TourAnchorKey.self, value: .bounds) { [target: $0] }
            .simultaneousGesture(TapGesture().onEnded {
                NotificationCenter.default.post(name: .tourTapped, object: target.rawValue)
            })
    }
}

// MARK: - Steps

private struct TourStep {
    /// nil = info-only step (no real control to ring on iOS, e.g. inside a sheet): card + Next.
    let target: TourTarget?
    let title: String
    let body: String
    /// true = the tour catches the tap (it would open a sheet / create something mid-tour).
    let swallow: Bool
}

// MARK: - View

struct SpotlightTutorialView: View {

    @Binding var isPresented: Bool
    let anchors: [TourTarget: Anchor<CGRect>]
    @EnvironmentObject private var appState: AppState

    @State private var step = -1 // -1 = welcome card
    @State private var missing = false
    @State private var pulse = false

    private let gold = Color(red: 0.784, green: 0.663, blue: 0.431)

    // Web's 16 steps plus the iOS-only "Back".
    // "Friends" sits after "Close the menu": on iOS the Friends button is in the home header, not the menu.
    private let steps: [TourStep] = [
        TourStep(target: .menuButton, title: "Menu", body: "Everything lives in the menu. Tap it.", swallow: false),
        TourStep(target: .cabinetAI, title: "AI Tools", body: "Your AI helpers live here. Tap to open.", swallow: false),
        TourStep(target: .yourStyle, title: "Your style", body: "Your style profile comes from your Instagram. Tap Build to read it (free). Valet and every dump use it.", swallow: false),
        TourStep(target: .scrub, title: "Instagram Scrub", body: "Pull photos from any public account. It also saves that account's style as a Dump Style, right below.", swallow: true),
        TourStep(target: .dumpStyles, title: "Dump Styles", body: "Looks you borrowed from scrubs. Turn one on and every dump comes out that way. Tap to look.", swallow: false),
        TourStep(target: .cabinetBack, title: "Back", body: "Tap the arrow to head back.", swallow: false),
        TourStep(target: .cabinetClose, title: "Close the menu", body: "Tap the X to head back.", swallow: false),
        TourStep(target: .friends, title: "Friends", body: "Find friends, peek at their dumps, leave comments.", swallow: true),
        TourStep(target: .dumpMenu, title: "Valet", body: "Meet your Valet. Tap the \u{22EF} button on a dump, then pick Valet.", swallow: true),
        TourStep(target: nil, title: "Valet is your AI assistant", body: "Chat with it to reorder photos, swap shots and set the vibe for this dump. It already knows your style and rules.", swallow: false),
        TourStep(target: .photoCard, title: "Pick a photo", body: "Tap any photo in a dump. Its \u{22EF} button appears when it's selected.", swallow: false),
        TourStep(target: .photoDots, title: "Recycle", body: "Now tap the \u{22EF} on the photo to open its menu.", swallow: true),
        TourStep(target: nil, title: "Recycle swaps a photo", body: "Recycle replaces this photo with a fresh one from your pool of unused photos. Same spot, new shot.", swallow: false),
        TourStep(target: .autoGen, title: "Auto Gen", body: "One tap builds your best carousel from your pool.", swallow: true),
        TourStep(target: .newDump, title: "New Dump", body: "Start an empty dump and fill it yourself.", swallow: true),
        TourStep(target: .pool, title: "The Pool", body: "Your unused photos wait here. Videos and captions have pools too. Tap it.", swallow: false),
        // Not swallowed: the tap really opens the credits sheet (invite link), then the tour ends. Mirrors web #81.
        TourStep(target: .credits, title: "Invite a friend", body: "Tap your credits to share your invite link. Earn 10 credits for each friend who finishes setup, enough for a new AI dump.", swallow: false),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if step < 0 {
                    welcome
                } else {
                    spotlight(geo: geo)
                }
                VStack {
                    HStack {
                        Spacer()
                        Button { dismiss() } label: {
                            Text("Skip ✕")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(Capsule().fill(Color(white: 0.1)))
                                .overlay(Capsule().stroke(Color.white.opacity(0.15)))
                        }
                    }
                    .padding(.top, 60).padding(.trailing, 16)
                    Spacer()
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tourTapped)) { note in
            guard step >= 0, let raw = note.object as? String, raw == steps[step].target?.rawValue else { return }
            advanceSoon()
        }
        .task(id: step) {
            missing = false
            if step >= 0, steps[step].target == nil { missing = true; return }   // info-only step: Next right away
            if step >= 0, steps[step].target == .pool { appState.scrollToPool = UUID() }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if step >= 0, let t = steps[step].target, anchors[t] == nil { missing = true }
        }
    }

    // MARK: Welcome

    private var welcome: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Welcome to Dumpster")
                    .font(.system(size: 24, weight: .heavy)).foregroundColor(.white)
                Text("A 1-minute tour. Tap the glowing spots to learn by doing.")
                    .font(.system(size: 14)).foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                Button { withAnimation { step = 0 } } label: {
                    Text("Start the tour")
                        .font(.system(size: 14, weight: .heavy)).foregroundColor(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(gold).clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(28).frame(maxWidth: 340)
        }
    }

    // MARK: Spotlight

    @ViewBuilder
    private func spotlight(geo: GeometryProxy) -> some View {
        let s = steps[step]
        if let t = s.target, let anchor = anchors[t] {
            let r = geo[anchor].insetBy(dx: -8, dy: -8)
            let upper = r.midY < geo.size.height / 2
            ZStack {
                // Four dim pieces so the hole passes taps to the real control.
                dim(CGRect(x: 0, y: 0, width: geo.size.width, height: max(0, r.minY)))
                dim(CGRect(x: 0, y: r.maxY, width: geo.size.width, height: max(0, geo.size.height - r.maxY)))
                dim(CGRect(x: 0, y: r.minY, width: max(0, r.minX), height: r.height))
                dim(CGRect(x: r.maxX, y: r.minY, width: max(0, geo.size.width - r.maxX), height: r.height))

                if s.swallow {
                    Color.clear.contentShape(Rectangle())
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                        .onTapGesture { advanceSoon() }
                }

                RoundedRectangle(cornerRadius: min(r.width, r.height) > 60 ? 16 : r.height / 2)
                    .strokeBorder(gold, lineWidth: 2)
                    .frame(width: r.width, height: r.height)
                    .shadow(color: gold.opacity(0.8), radius: pulse ? 16 : 6)
                    .scaleEffect(pulse ? 1.05 : 1.0)
                    .position(x: r.midX, y: r.midY)
                    .allowsHitTesting(false)

                Image(systemName: upper ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 22)).foregroundColor(gold)
                    .shadow(color: gold.opacity(0.8), radius: 6)
                    .offset(y: pulse ? (upper ? 6 : -6) : 0)
                    .position(x: r.midX, y: upper ? r.maxY + 22 : r.minY - 22)
                    .allowsHitTesting(false)

                card(s)
                    .frame(maxWidth: 360)
                    .padding(.horizontal, 16)
                    .position(x: geo.size.width / 2, y: upper ? geo.size.height - 120 : 150)
            }
        } else {
            ZStack {
                Color.black.opacity(0.8).ignoresSafeArea()
                card(s).frame(maxWidth: 360).padding(.horizontal, 16)
                    .position(x: geo.size.width / 2, y: geo.size.height - 120)
            }
        }
    }

    private func dim(_ rect: CGRect) -> some View {
        Color.black.opacity(0.8)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }

    private func card(_ s: TourStep) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("STEP \(step + 1) OF \(steps.count)")
                .font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundColor(.white.opacity(0.4))
            Text(s.title).font(.system(size: 17, weight: .heavy)).foregroundColor(.white)
            Text(s.body).font(.system(size: 13)).foregroundColor(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            if missing {
                Button { advance() } label: {
                    Text("Next").font(.system(size: 12, weight: .heavy)).foregroundColor(.black)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(gold).clipShape(RoundedRectangle(cornerRadius: 10))
                }.padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18).padding(.vertical, 16)
        .background(Color(white: 0.08))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12)))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.6), radius: 24)
    }

    // MARK: Actions

    private func advanceSoon() {
        let current = step
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if step == current { advance() }
        }
    }

    private func advance() {
        if step >= steps.count - 1 {
            // Last step ("Invite a friend"): open the credits sheet whether reached by tapping the pill or Next.
            if AuthManager.shared.isSignedIn { CreditManager.shared.showOutOfCredits = true }
            dismiss()
        } else { withAnimation(.easeInOut(duration: 0.2)) { step += 1 } }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) { isPresented = false }
    }
}
