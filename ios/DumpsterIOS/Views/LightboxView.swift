import SwiftUI
import SwiftData

/// Full-screen photo overlay shown when `appState.lightboxPhotoId != nil`.
/// Tap backdrop or X button to dismiss.
struct LightboxView: View {

    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query private var allPhotos: [DumpPhoto]

    private var photo: DumpPhoto? {
        guard let id = appState.lightboxPhotoId else { return nil }
        return allPhotos.first { $0.id == id }
    }

    var body: some View {
        if let photo = photo {
            ZStack {
                Color.black.opacity(0.92)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }

                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.white.opacity(0.75))
                        }
                        .padding(20)
                    }

                    Spacer()

                    if let img = PhotoStorageManager.shared.loadImage(relativePath: photo.localPath) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 16)
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 80))
                            .foregroundColor(.white.opacity(0.3))
                    }

                    HStack(spacing: 12) {
                        Text(photo.category.uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.0)
                            .foregroundColor(appState.accentColor)
                        Text(photo.filename)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if photo.isHuji {
                            Text("HUJI")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundColor(.red)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.18))
                                .cornerRadius(4)
                        }
                    }
                    .padding(.top, 14)
                    .padding(.horizontal, 20)

                    Spacer()
                }
            }
            .transition(.opacity)
        }
    }

    private func dismiss() {
        withAnimation(.easeInOut(duration: 0.22)) {
            appState.lightboxPhotoId = nil
        }
    }
}
