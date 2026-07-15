import SwiftUI

/// Confetti burst — fires every time `trigger` increments. Lee's pick from the
/// Motion Library ("pull confetti from Magic UI"), wired to Dumpster's actual
/// celebration moment: a completed dump export/share, not decoration.
struct ConfettiView: View {
    let trigger: Int
    @State private var particles: [Particle] = []

    fileprivate struct Particle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var color: Color
        var size: CGFloat
        var rotation: Double
        var delay: Double
        var duration: Double
        var driftX: CGFloat
    }

    private static let colors: [Color] = [
        Color(red: 0.784, green: 0.663, blue: 0.431), // gold — matches app accent
        .white, .red, .green, .blue, .yellow, .pink
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(particles) { p in
                    ConfettiPiece(particle: p, screenHeight: geo.size.height)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .onChange(of: trigger) { _, newValue in
            guard newValue > 0 else { return }
            burst()
        }
    }

    private func burst() {
        let screenWidth = UIScreen.main.bounds.width
        particles = (0..<50).map { _ in
            Particle(
                x: CGFloat.random(in: 0...screenWidth),
                color: Self.colors.randomElement()!,
                size: CGFloat.random(in: 6...11),
                rotation: Double.random(in: 0...360),
                delay: Double.random(in: 0...0.25),
                duration: Double.random(in: 1.4...2.1),
                driftX: CGFloat.random(in: -60...60)
            )
        }
        // ponytail: fixed clear-delay rather than tracking per-burst completion —
        // a rapid double-export could clip the tail of the second burst early.
        // Upgrade to a per-burst id/cancellation if that turns out to matter.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            particles = []
        }
    }
}

private struct ConfettiPiece: View {
    let particle: ConfettiView.Particle
    let screenHeight: CGFloat
    @State private var fallen = false

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(particle.color)
            .frame(width: particle.size, height: particle.size * 0.4)
            .rotationEffect(.degrees(fallen ? particle.rotation + 360 : particle.rotation))
            .position(x: particle.x + (fallen ? particle.driftX : 0), y: fallen ? screenHeight + 40 : -20)
            .opacity(fallen ? 0 : 1)
            .onAppear {
                withAnimation(.easeIn(duration: particle.duration).delay(particle.delay)) {
                    fallen = true
                }
            }
    }
}
