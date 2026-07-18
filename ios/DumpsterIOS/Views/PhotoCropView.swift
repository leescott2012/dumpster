import SwiftUI
import SwiftData

/// Full-screen crop overlay shown when `appState.cropPhotoId != nil`.
/// Pan/zoom the image under a fixed-aspect crop frame (matches the app's
/// 4:5 carousel tile ratio), then snapshot exactly what's visible via
/// ImageRenderer — WYSIWYG, no manual pixel-math crop-rect calculation.
struct PhotoCropView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query private var allPhotos: [DumpPhoto]

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var isSaving = false

    // 4:5 — matches DumpCardView's carousel tile aspect (145x195 / PhotoPoolView tiles).
    private let frameSize = CGSize(width: 300, height: 375)

    private var photo: DumpPhoto? {
        guard let id = appState.cropPhotoId else { return nil }
        return allPhotos.first { $0.id == id }
    }

    var body: some View {
        if let photo, let image = PhotoStorageManager.shared.loadImage(relativePath: photo.localPath) {
            ZStack {
                Color.black.opacity(0.95).ignoresSafeArea()

                VStack(spacing: 24) {
                    Text("Crop Photo")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.top, 70)

                    cropCanvas(image: image)

                    Text("Pinch to zoom, drag to reposition")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))

                    Spacer()

                    HStack(spacing: 16) {
                        Button("Cancel") { dismiss() }
                            .foregroundColor(.white.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        Button(action: { save(image: image, photo: photo) }) {
                            Group {
                                if isSaving {
                                    ProgressView().progressViewStyle(.circular).tint(.black)
                                } else {
                                    Text("Save").fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .foregroundColor(.black)
                        .padding(.vertical, 14)
                        .background(appState.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .disabled(isSaving)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func cropCanvas(image: UIImage) -> some View {
        let dragGesture = DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in lastOffset = offset }

        let magnifyGesture = MagnificationGesture()
            .onChanged { value in scale = max(1.0, lastScale * value) }
            .onEnded { _ in lastScale = scale }

        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: frameSize.width, height: frameSize.height)
            .scaleEffect(scale)
            .offset(offset)
            .frame(width: frameSize.width, height: frameSize.height)
            .clipped()
            .contentShape(Rectangle())
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white, lineWidth: 2))
            .gesture(SimultaneousGesture(dragGesture, magnifyGesture))
    }

    private func save(image: UIImage, photo: DumpPhoto) {
        isSaving = true
        let renderer = ImageRenderer(content: cropCanvas(image: image))
        // Retina-equivalent output — the crop frame is only 300x375pt, so a
        // 1x render would be visibly soft next to the app's other tiles.
        renderer.scale = 3.0
        guard let cropped = renderer.uiImage else { isSaving = false; return }

        let oldPath = photo.localPath
        photo.localPath = PhotoStorageManager.shared.saveImage(cropped)
        try? modelContext.save()
        PhotoStorageManager.shared.deleteImage(relativePath: oldPath)

        isSaving = false
        dismiss()
    }

    private func dismiss() {
        scale = 1.0; lastScale = 1.0
        offset = .zero; lastOffset = .zero
        appState.cropPhotoId = nil
    }
}
