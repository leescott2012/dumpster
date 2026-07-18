import SwiftUI

/// "Marvel intro" style flip-through: the user's own pool photos hard-cut
/// past rapidly, punching in then shrinking/collapsing toward the logo as
/// they cut away — like each one gets swept into the bin — under a dark
/// scrim carrying the Dumpster logo + a kinetic letter-slam "DUMPSTER"
/// wordmark (same per-letter spring treatment as the web "Kinetic Text /
/// Word Slam" effect in the Motion Library — ported here rather than
/// reinvented). Plays once on app launch, then hands off via onComplete.
struct DumpFlipIntroView: View {
    let photos: [DumpPhoto]
    let onComplete: () -> Void

    @State private var index = 0
    @State private var flipCount = 0
    @State private var finished = false
    // Slow counterclockwise drift applied to the photo layer only — the logo
    // must stay locked/centered, so rotation never touches it.
    @State private var rotation: Double = 0
    // Logo grows the whole intro, easeIn so it accelerates near the end —
    // the "sucked into the center" zoom-in feeling on the way out.
    @State private var logoScale: CGFloat = 1.0
    // Ramps the scrim to fully opaque black; wordmark waits for this to land.
    @State private var blackout: Double = 0
    @State private var wordmarkVisible = false

    // Fixed total length regardless of flip count — flips fill the first
    // portion, then the last photo holds while black + wordmark take over.
    private let introDuration: Double = 4.0
    private let flipPhaseDuration: Double = 2.6
    private let totalFlips = 13
    private var interval: Double { flipPhaseDuration / Double(totalFlips) } // ~0.2s — slower than the old 0.11s
    // ponytail: fractional anchor tuned by hand to where the logo actually
    // sits in the VStack below (84pt logo + 16pt spacing above the
    // wordmark) — re-tune if that layout changes.
    private let binAnchor = UnitPoint(x: 0.5, y: 0.47)

    var body: some View {
        ZStack {
            if !photos.isEmpty,
               let img = PhotoStorageManager.shared.loadImage(relativePath: photos[index % photos.count].localPath) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .id(index)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 1.2).combined(with: .opacity),
                        removal: .scale(scale: 0.04, anchor: binAnchor).combined(with: .opacity)
                    ))
                    .rotationEffect(.degrees(rotation))
            }

            // Shadowed overlay carrying the brand mark, so the wordmark and
            // logo stay legible over whatever photo happens to be flipping.
            // Starts darker than before, then ramps to fully opaque black.
            LinearGradient(
                colors: [Color.black.opacity(0.45), Color.black.opacity(0.72)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            Color.black.opacity(blackout).ignoresSafeArea()

            // Logo: centered, locked (no position animation, only scale), enlarges throughout.
            VStack(spacing: 16) {
                Image("DumpsterLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.6), radius: 24, y: 10)
                    .scaleEffect(logoScale)

                // Same letter-slam effect as before — just held back until the
                // scrim reaches full black instead of firing immediately.
                if wordmarkVisible {
                    KineticSlamText(text: "DUMPSTER")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: index)
        .onAppear {
            if photos.isEmpty { onComplete(); return }

            withAnimation(.linear(duration: introDuration)) { rotation = -18 }
            withAnimation(.easeIn(duration: introDuration)) { logoScale = 2.4 }
            withAnimation(.easeIn(duration: introDuration * 0.8)) { blackout = 1.0 }

            DispatchQueue.main.asyncAfter(deadline: .now() + introDuration * 0.8) {
                wordmarkVisible = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + introDuration) {
                finished = true
                onComplete()
            }
        }
        .onReceive(Timer.publish(every: interval, on: .main, in: .common).autoconnect()) { _ in
            guard !finished, !photos.isEmpty, flipCount < totalFlips else { return }
            flipCount += 1
            index += 1
        }
    }
}

/// Letter-by-letter spring slam-in — native port of the Motion Library's
/// "Kinetic Text / Word Slam" (already live on web as the Draft 2 headlines).
private struct KineticSlamText: View {
    let text: String
    var font: Font = .system(size: 32, weight: .heavy, design: .rounded)
    var color: Color = Color(hex: "#C8A96E")
    var letterDelay: Double = 0.045

    @State private var appeared = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(text.enumerated()), id: \.offset) { i, ch in
                Text(String(ch))
                    .font(font)
                    .tracking(1)
                    .foregroundColor(color)
                    .rotationEffect(.degrees(appeared ? 0 : -10))
                    .offset(y: appeared ? 0 : 46)
                    .opacity(appeared ? 1 : 0)
                    .animation(
                        .spring(response: 0.5, dampingFraction: 0.62).delay(Double(i) * letterDelay),
                        value: appeared
                    )
            }
        }
        .onAppear { appeared = true }
    }
}
