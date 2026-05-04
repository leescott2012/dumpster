import SwiftUI
import SwiftData

/// Reusable photo tile used by both the pool grid and dump carousels.
///
/// Visual states (mutually compatible):
///   • default      — image fills, rounded corners
///   • starred      — gold star badge top-left (both contexts)
///   • selected     — green border + green tint (add-to-dump mode)
///   • used (pool)  — 40% black overlay + checkmark badge
///   • dragging     — gold border + 1.05 scale (dump context only)
///
/// Context rules:
///   • pool context  — no slot number, no category label, shows "Delete Photo" in menu
///   • dump context  — slot number pill, category gradient, shows "Remove from Dump" in menu
struct PhotoCardView: View {

    enum CardContext {
        case pool
        case dump(dumpId: String)
    }

    let photo: DumpPhoto
    let context: CardContext
    var isSelected: Bool = false
    var isUsed: Bool = false
    var slotIndex: Int? = nil
    var totalInDump: Int? = nil
    var size: CGSize = CGSize(width: 160, height: 200)

    var onTap: (() -> Void)? = nil
    var onDoubleTap: (() -> Void)? = nil
    var onRemoveFromDump: (() -> Void)? = nil
    var onToggleStar: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onOpenLightbox: (() -> Void)? = nil

    @EnvironmentObject var appState: AppState
    @State private var showMenu = false
    @State private var isDragging = false

    private var isDumpContext: Bool {
        if case .dump = context { return true }
        return false
    }

    var body: some View {
        ZStack {
            imageLayer
            if isUsed { usedOverlay }
            if isSelected { selectedOverlay }
            if isDumpContext { categoryGradient }
            badgeLayer
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(borderOverlay)
        .scaleEffect(isDragging ? 1.05 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isDragging)
        // Order matters: double-tap first so SwiftUI can disambiguate.
        .onTapGesture(count: 2) {
            if let onDoubleTap { onDoubleTap() }
            else { appState.lightboxPhotoId = photo.id }
        }
        .onTapGesture(count: 1) {
            if appState.addingToDumpId != nil && !isDumpContext {
                onTap?()
            } else {
                showMenu = true
            }
        }
        .confirmationDialog(photo.filename, isPresented: $showMenu, titleVisibility: .hidden) {
            Button(photo.starred ? "Unfavorite" : "Favorite") { onToggleStar?() }
            Button("Open Lightbox") {
                if let onOpenLightbox { onOpenLightbox() }
                else { appState.lightboxPhotoId = photo.id }
            }
            if isDumpContext {
                Button("Remove from Dump", role: .destructive) { onRemoveFromDump?() }
            } else {
                Button("Delete Photo", role: .destructive) { onDelete?() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Layers

    private var imageLayer: some View {
        Group {
            if let img = PhotoStorageManager.shared.loadImage(relativePath: photo.localPath) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(Color.gray.opacity(0.2))
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                            .font(.system(size: 28))
                    )
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private var usedOverlay: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.4)
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.white)
                .font(.system(size: 14))
                .padding(6)
        }
    }

    private var selectedOverlay: some View {
        ZStack(alignment: .center) {
            Color.green.opacity(0.2)
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 24))
        }
    }

    /// Category label gradient — only shown in dump context.
    private var categoryGradient: some View {
        VStack {
            Spacer()
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [Color.black.opacity(0.7), Color.clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .frame(height: 36)
                Text(photo.category.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
            }
        }
    }

    @ViewBuilder
    private var badgeLayer: some View {
        VStack {
            HStack(alignment: .top, spacing: 4) {
                // Slot number pill — dump context only
                if isDumpContext, let idx = slotIndex {
                    Text(String(format: "%02d", idx + 1))
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .padding(7)
                }
                if photo.starred {
                    Image(systemName: "star.fill")
                        .foregroundColor(Theme.starBadge)
                        .font(.system(size: 11))
                        .padding(5)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                        .padding(6)
                }
                Spacer()
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        let cornerRadius: CGFloat = 10
        if isDragging {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Theme.gold, lineWidth: 2)
        } else if isSelected {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Color.green, lineWidth: 2)
        } else {
            EmptyView()
        }
    }
}
