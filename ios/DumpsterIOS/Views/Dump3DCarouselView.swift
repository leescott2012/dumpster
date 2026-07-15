import SwiftUI

/// "Preview in 3D" — Lee's pick from the Motion Library (Cult UI's
/// three-d-carousel). Photos orbit in a ring you can grab and spin; a
/// share-preview / "view the dump as a physical object" mode, distinct from
/// the working drag-to-reorder carousel in DumpCardView.
struct Dump3DCarouselView: View {
    let dump: PhotoDump
    let photos: [DumpPhoto]

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    @State private var rotation: Double = 0
    @State private var isDragging = false
    @State private var lastDragX: CGFloat = 0

    private let radius: CGFloat = 130
    private let cardSize = CGSize(width: 110, height: 140)
    // ponytail: ring caps at 12 for legibility on a phone screen — a "preview
    // the vibe" mode, not a functional full list. Raise if a wider dump makes
    // the cap feel wrong in practice.
    private let maxRingCount = 12

    private var ringPhotos: [DumpPhoto] { Array(photos.prefix(maxRingCount)) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ZStack {
                ForEach(Array(ringPhotos.enumerated()), id: \.element.id) { index, photo in
                    ringCard(photo: photo, index: index, total: ringPhotos.count)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.75))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .padding(.trailing, 20)
                }
                .padding(.top, 70)

                Spacer()

                VStack(spacing: 4) {
                    Text(dump.title.uppercased())
                        .font(.system(size: 13, weight: .heavy))
                        .tracking(2)
                        .foregroundColor(appState.accentColor)
                    Text("\(photos.count) photo\(photos.count == 1 ? "" : "s") · drag to spin")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.bottom, 50)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    isDragging = true
                    rotation += Double(value.translation.width - lastDragX) * 0.35
                    lastDragX = value.translation.width
                }
                .onEnded { _ in
                    isDragging = false
                    lastDragX = 0
                }
        )
        .onReceive(Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()) { _ in
            guard !isDragging else { return }
            rotation += 0.12
        }
    }

    @ViewBuilder
    private func ringCard(photo: DumpPhoto, index: Int, total: Int) -> some View {
        let step = 360.0 / Double(max(total, 1))
        let angleDeg = step * Double(index) + rotation
        let radians = angleDeg * .pi / 180
        let depth = cos(radians)                          // -1 (back) ... 1 (front)
        let xOffset = sin(radians) * radius
        let scale = 0.55 + (depth + 1) / 2 * 0.45          // 0.55 ... 1.0
        let opacity = 0.35 + (depth + 1) / 2 * 0.65        // 0.35 ... 1.0

        Group {
            if let img = PhotoStorageManager.shared.loadImage(relativePath: photo.localPath) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(Color.gray.opacity(0.2))
            }
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 10, y: 8)
        .scaleEffect(scale)
        .offset(x: xOffset)
        .opacity(opacity)
        .zIndex(depth)
    }
}
