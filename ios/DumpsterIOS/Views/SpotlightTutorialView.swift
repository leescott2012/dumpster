import SwiftUI

// MARK: - Data

struct TutorialStep {
    let title: String
    /// Each string becomes a glowing-circle bullet in the card.
    let bullets: [String]
    /// Normalized (0–1) oval within screen size. nil = full-scrim centered card.
    let frame: CGRect?
}

// MARK: - View

/// Spotlight-style tutorial overlay. Sits on top of the live app (not a fullScreenCover),
/// so the real UI is visible through the glowing oval cutout.
struct SpotlightTutorialView: View {

    @Binding var isPresented: Bool

    @State private var step = 0
    @State private var glowPulse: Double = 0.4

    private let gold = Color(red: 0.784, green: 0.663, blue: 0.431) // #C8A96E

    // ── Steps ──────────────────────────────────────────────────────
    // Normalized frames for iPhone 17 Pro (393 × 852 pt).
    // DI bar reserves ~54 pt at top; content starts after Color.clear(height:50).

    private let steps: [TutorialStep] = [
        // 0 — Welcome (centered card, no spotlight)
        TutorialStep(
            title: "Welcome to Dumpster ✦",
            bullets: [
                "Build perfect Instagram carousels fast",
                "Curate, reorder, and export in minutes",
                "AI captions built right in"
            ],
            frame: nil
        ),
        // 1 — Stats chips (narrow oval across the three chips)
        TutorialStep(
            title: "Stats at a Glance",
            bullets: [
                "Dump count — total carousels in progress",
                "Photos Used — across all active dumps",
                "In Pool — still available to add"
            ],
            frame: CGRect(x: 0.02, y: 0.226, width: 0.74, height: 0.048)
        ),
        // 2 — Dump card (oval around first dump card)
        TutorialStep(
            title: "Photo Dumps",
            bullets: [
                "Drag photos left/right to reorder",
                "Tap the title to rename the dump",
                "Gold bar = sweet spot (10–12 photos)"
            ],
            frame: CGRect(x: 0.02, y: 0.295, width: 0.96, height: 0.375)
        ),
        // 3 — Sparkles icon (tight circle on the sparkles button)
        TutorialStep(
            title: "AI Captions ✦",
            bullets: [
                "Generates caption options instantly",
                "Tap ✦ on any dump to try it",
                "Add your API key in Main Menu → AI"
            ],
            frame: CGRect(x: 0.655, y: 0.305, width: 0.095, height: 0.044)
        ),
        // 4 — Done (centered card, no spotlight)
        TutorialStep(
            title: "You're All Set!",
            bullets: [
                "Scroll down to explore the Photo Pool",
                "Pinch to resize the grid (S / M / L)",
                "Tap ≡ anytime to replay this tour"
            ],
            frame: nil
        ),
    ]

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                spotlightLayer(geo: geo)
                    .id(step)
                    .transition(.opacity.animation(.easeInOut(duration: 0.28)))

                // Skip button — always top-right
                VStack {
                    HStack {
                        Spacer()
                        Button("Skip") { dismiss() }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.40))
                            .padding(.top, 68)
                            .padding(.trailing, 22)
                    }
                    Spacer()
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                glowPulse = 1.0
            }
        }
    }

    // MARK: - Spotlight layer

    @ViewBuilder
    private func spotlightLayer(geo: GeometryProxy) -> some View {
        let current = steps[step]

        if let norm = current.frame {
            let abs  = norm.toAbsolute(in: geo.size)
            let hole = abs.insetBy(dx: -12, dy: -12)

            // Dark scrim with even-odd oval hole
            Path { p in
                p.addRect(CGRect(origin: .zero, size: geo.size))
                p.addEllipse(in: hole)
            }
            .fill(Color.black.opacity(0.82), style: FillStyle(eoFill: true))
            .ignoresSafeArea()

            // Pulsing gold glow ring (oval)
            Ellipse()
                .strokeBorder(gold.opacity(glowPulse), lineWidth: 2)
                .frame(width: hole.width, height: hole.height)
                .shadow(color: gold.opacity(0.6), radius: 12)
                .shadow(color: gold.opacity(0.3), radius: 24)
                .position(x: hole.midX, y: hole.midY)

            // Tooltip card above or below
            tooltipCard(step: current, hole: hole, geo: geo)

        } else {
            // Centered card — full scrim
            Color.black.opacity(0.88)
                .ignoresSafeArea()
                .onTapGesture { } // swallow taps

            centeredCard(step: current)
        }
    }

    // MARK: - Tooltip card (above or below spotlight)

    @ViewBuilder
    private func tooltipCard(step: TutorialStep, hole: CGRect, geo: GeometryProxy) -> some View {
        let cardW: CGFloat = min(geo.size.width - 40, 310)
        let arrowH: CGFloat = 9
        let gap: CGFloat = 10

        let spaceBelow = geo.size.height - hole.maxY
        let placeBelow = spaceBelow >= 200

        let idealX   = hole.midX
        let clampedX = max(cardW / 2 + 16, min(geo.size.width - cardW / 2 - 16, idealX))
        let arrowDX  = idealX - clampedX

        let approxCardH: CGFloat = 160
        let centerY: CGFloat = placeBelow
            ? hole.maxY + gap + arrowH + approxCardH / 2
            : hole.minY - gap - arrowH - approxCardH / 2

        VStack(spacing: 0) {
            if placeBelow  { arrowTriangle(.up,   dx: arrowDX) }
            cardBody(step: step, width: cardW)
            if !placeBelow { arrowTriangle(.down, dx: arrowDX) }
        }
        .frame(width: cardW)
        .position(x: clampedX, y: centerY)
    }

    // MARK: - Arrow triangle

    private func arrowTriangle(_ dir: ArrowDir, dx: CGFloat) -> some View {
        HStack(spacing: 0) {
            Spacer().frame(width: max(8, 22 + dx))
            ArrowShape(direction: dir)
                .fill(Color(white: 0.11))
                .frame(width: 16, height: 9)
            Spacer()
        }
    }

    // MARK: - Tooltip card body

    private func cardBody(step: TutorialStep, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(step.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(gold)

            bulletList(step.bullets)

            HStack {
                pageDots
                Spacer()
                nextButton
            }
        }
        .padding(16)
        .background(Color(white: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Centered card (welcome / done)

    private func centeredCard(step: TutorialStep) -> some View {
        VStack(spacing: 20) {
            Image(systemName: step.title.contains("Set") ? "checkmark.circle" : "sparkles")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(gold)
                .shadow(color: gold.opacity(0.5), radius: 10)

            Text(step.title)
                .font(.system(size: 21, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            bulletList(step.bullets)
                .frame(maxWidth: 280, alignment: .leading)

            pageDots.padding(.top, 2)
            nextButton
        }
        .padding(26)
        .frame(maxWidth: 340)
        .background(Color(white: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.5), radius: 28)
    }

    // MARK: - Bullet list with glowing gold circles

    private func bulletList(_ bullets: [String]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(bullets, id: \.self) { bullet in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(gold)
                        .frame(width: 5, height: 5)
                        .shadow(color: gold.opacity(0.9), radius: 5)
                        .shadow(color: gold.opacity(0.5), radius: 10)
                        .padding(.top, 5)
                    Text(bullet)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.80))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Page dots

    private var pageDots: some View {
        HStack(spacing: 5) {
            ForEach(0..<steps.count, id: \.self) { i in
                if i == self.step {
                    Capsule()
                        .fill(gold)
                        .frame(width: 14, height: 5)
                        .shadow(color: gold.opacity(0.6), radius: 4)
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.20))
                        .frame(width: 5, height: 5)
                }
            }
        }
    }

    // MARK: - Next button

    private var nextButton: some View {
        Button(step < steps.count - 1 ? "NEXT" : "GET STARTED") {
            advance()
        }
        .font(.system(size: 11, weight: .heavy))
        .tracking(0.8)
        .foregroundColor(.black)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(gold)
        .clipShape(Capsule())
        .shadow(color: gold.opacity(0.4), radius: 8)
    }

    // MARK: - Actions

    private func advance() {
        if step < steps.count - 1 {
            withAnimation(.easeInOut(duration: 0.25)) { step += 1 }
        } else {
            dismiss()
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) { isPresented = false }
    }
}

// MARK: - Arrow direction

private enum ArrowDir { case up, down }

// MARK: - Arrow triangle shape

private struct ArrowShape: Shape {
    let direction: ArrowDir
    func path(in rect: CGRect) -> Path {
        var p = Path()
        switch direction {
        case .up:
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        case .down:
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - CGRect helper

private extension CGRect {
    func toAbsolute(in size: CGSize) -> CGRect {
        CGRect(
            x: minX * size.width,
            y: minY * size.height,
            width: width  * size.width,
            height: height * size.height
        )
    }
}
