import SwiftUI

/// "Marvel intro" style flip-through: photos hard-cut past rapidly with a
/// scale-punch, building to the 3D carousel ring settling in behind it.
/// A fixed, non-interactive flourish (unlike the ring) — plays once, then
/// hands off via onComplete.
struct DumpFlipIntroView: View {
    let photos: [DumpPhoto]
    let onComplete: () -> Void

    @State private var index = 0
    @State private var flipCount = 0
    @State private var finished = false

    private let totalFlips = 16
    private let interval = 0.11

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
                        removal: .opacity
                    ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: index)
        .onAppear {
            if photos.isEmpty { onComplete() }
        }
        .onReceive(Timer.publish(every: interval, on: .main, in: .common).autoconnect()) { _ in
            guard !finished, !photos.isEmpty else { return }
            flipCount += 1
            if flipCount >= totalFlips {
                finished = true
                onComplete()
            } else {
                index += 1
            }
        }
    }
}
