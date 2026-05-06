import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    private let gold = Color(red: 200/255, green: 169/255, blue: 110/255)

    @State private var currentPage = 0

    private let steps: [OnboardingStep] = [
        OnboardingStep(icon: "sparkles", title: "Welcome to Dumpster", body: "Your personal Instagram carousel studio. Build perfect photo dumps in minutes."),
        OnboardingStep(icon: "photo.on.rectangle.angled", title: "Your Photo Pool", body: "Upload all your photos here. They sit in the pool until you add them to a dump. Tap + in the pool to add photos."),
        OnboardingStep(icon: "rectangle.stack", title: "Build Dumps", body: "Each dump is one carousel. Drag photos left or right to reorder. Aim for 10\u{2013}12 photos \u{2014} that's the peak."),
        OnboardingStep(icon: "wand.and.stars", title: "Auto-Generate", body: "Tap AUTO-GENERATE and Vision AI will cluster your photos into perfectly themed dumps automatically."),
        OnboardingStep(icon: "text.bubble", title: "AI Captions", body: "Tap the sparkles icon on any dump to generate AI captions instantly. Add your API key in settings for the best results."),
        OnboardingStep(icon: "checkmark.seal.fill", title: "You're Ready!", body: "Start by uploading photos to your pool, then build your first dump. Swipe the carousel to preview your flow.")
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip
                HStack {
                    Spacer()
                    if currentPage < steps.count - 1 {
                        Button("Skip") { isPresented = false }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.horizontal, 24)
                            .padding(.top, 60)
                    } else {
                        Color.clear.frame(height: 1).padding(.top, 60)
                    }
                }

                Spacer()

                // Icon
                Image(systemName: steps[currentPage].icon)
                    .font(.system(size: 64, weight: .light))
                    .foregroundColor(gold)
                    .id("icon_\(currentPage)")
                    .transition(.scale(scale: 0.8).combined(with: .opacity))

                Spacer().frame(height: 40)

                // Title
                Text(steps[currentPage].title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .id("title_\(currentPage)")
                    .transition(.opacity)

                Spacer().frame(height: 16)

                // Body
                Text(steps[currentPage].body)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .padding(.horizontal, 40)
                    .id("body_\(currentPage)")
                    .transition(.opacity)

                Spacer()

                // Page dots
                HStack(spacing: 8) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        Circle()
                            .fill(i == currentPage ? gold : Color.white.opacity(0.2))
                            .frame(width: i == currentPage ? 8 : 5, height: i == currentPage ? 8 : 5)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                    }
                }
                .padding(.bottom, 32)

                // Next / Get Started button
                Button {
                    if currentPage < steps.count - 1 {
                        withAnimation(.easeInOut(duration: 0.3)) { currentPage += 1 }
                    } else {
                        isPresented = false
                    }
                } label: {
                    Text(currentPage < steps.count - 1 ? "NEXT" : "GET STARTED")
                        .font(.system(size: 13, weight: .heavy))
                        .tracking(2.5)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(gold)
                        .clipShape(Capsule())
                        .shadow(color: gold.opacity(0.3), radius: 12, x: 0, y: 4)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 52)
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct OnboardingStep {
    let icon: String
    let title: String
    let body: String
}
