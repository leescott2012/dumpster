import SwiftUI
import SwiftData
import Photos

struct PhotoMenuSheet: View {
    let photo: DumpPhoto           // the DumpPhoto model
    let isDumpContext: Bool
    var isDuplicate: Bool = false
    var onLightbox: () -> Void = {}
    var onCrop: () -> Void = {}
    var onSaveToPhotos: () -> Void = {}
    var onDismissDuplicate: () -> Void = {}
    var onRescan: () -> Void = {}
    var onRemove: () -> Void = {}     // remove from dump OR delete from pool
    @Environment(\.dismiss) private var dismiss
    @State private var showFind = false

    private let gold = Color(red: 200/255, green: 169/255, blue: 110/255)

    var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()
            VStack(spacing: 0) {
                // Handle
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)
                    .padding(.bottom, 16)

                // Items
                menuItem(icon: "arrow.up.left.and.arrow.down.right", label: "Lightbox", tint: .white) {
                    onLightbox(); dismiss()
                }
                Divider().background(Color.white.opacity(0.07))
                menuItem(icon: "crop", label: "Crop", tint: .white) {
                    onCrop(); dismiss()
                }
                Divider().background(Color.white.opacity(0.07))
                menuItem(icon: "square.and.arrow.down", label: "Save to Photos", tint: .white) {
                    onSaveToPhotos(); dismiss()
                }
                Divider().background(Color.white.opacity(0.07))
                menuItem(icon: "magnifyingglass", label: "Find in Photos", tint: .white) {
                    showFind = true
                }
                if isDuplicate {
                    Divider().background(Color.white.opacity(0.07))
                    menuItem(icon: "checkmark.circle", label: "Not a duplicate", tint: .white) {
                        onDismissDuplicate(); dismiss()
                    }
                }
                Divider().background(Color.white.opacity(0.07))
                // Rescan AI Labels — greyed out (premium)
                HStack(spacing: 14) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.25))
                        .frame(width: 22)
                    Text("Rescan AI Labels")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.25))
                    Spacer()
                    Text("PREMIUM")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.2)
                        .foregroundColor(gold.opacity(0.5))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .overlay(Capsule().strokeBorder(gold.opacity(0.3), lineWidth: 0.8))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                Divider().background(Color.white.opacity(0.07))
                // Destructive
                Button {
                    HapticManager.shared.playRemove()
                    onRemove(); dismiss()
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: isDumpContext ? "minus.circle" : "trash")
                            .font(.system(size: 15))
                            .foregroundColor(.red)
                            .frame(width: 22)
                        Text(isDumpContext ? "Remove from Dump" : "Delete Photo")
                            .font(.system(size: 15))
                            .foregroundColor(.red)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
                Spacer()
            }
        }
        .presentationDetents([.height(isDuplicate ? 378 : 330)])
        .presentationDragIndicator(.hidden)
        .preferredColorScheme(.dark)
        .alert("Find in Photos", isPresented: $showFind) {
            Button("Open Photos") {
                if let u = URL(string: "photos-redirect://") { UIApplication.shared.open(u) }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text(findMessage) }
    }

    /// iOS can't open a specific photo inside the Photos app, so show exactly when/where it was
    /// taken, then open Photos so the user can scroll straight to it.
    private var findMessage: String {
        guard let t = photo.takenAt else {
            return "This photo has no saved date (likely a screenshot or edited image). Look near when you imported it."
        }
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d, yyyy 'at' h:mm a"
        var lines = ["Taken " + f.string(from: t)]
        if let lat = photo.lat, let lng = photo.lng { lines.append(String(format: "Near %.3f, %.3f", lat, lng)) }
        lines.append("In Photos, scroll to that date.")
        return lines.joined(separator: "\n")
    }

    private func menuItem(icon: String, label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(tint)
                    .frame(width: 22)
                Text(label)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }
}
