import SwiftUI

// MARK: - DumpMenuSheet
//
// Bottom sheet presented when the user taps the "..." button on a DumpCardView.
// Action set mirrors web DumpActionSheet.tsx: rate (thumbs up/down), favorite,
// Valet (AI chat), captions, export/share, archive, delete — plus the
// iOS-only "Send to Instagram" shortcut.

struct DumpMenuSheet: View {
    let dump: PhotoDump
    let isGenerating: Bool
    let photosEmpty: Bool
    let hasCaptions: Bool
    let onChat: () -> Void
    let onCaptions: () -> Void
    let onShare: () -> Void
    let onPreview3D: () -> Void
    let onInstagram: () -> Void
    let onDelete: () -> Void
    let onHeart: () -> Void
    let onRate: (String?) -> Void
    let onArchive: () -> Void

    @Environment(\.dismiss) private var dismiss
    private let gold = Color(hex: "#C8A96E")

    var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()

            VStack(spacing: 0) {
                // Drag handle
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)
                    .padding(.bottom, 16)

                // Dump title
                Text(dump.title.uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(gold)
                    .padding(.bottom, 16)

                rateRow

                Divider().background(Color.white.opacity(0.07))

                // Favorite / Unfavorite
                menuItem(
                    icon: dump.liked ? "heart.fill" : "heart",
                    label: dump.liked ? "Unfavorite" : "Favorite",
                    tint: dump.liked ? .red : .white
                ) {
                    onHeart()
                    dismiss()
                }

                Divider().background(Color.white.opacity(0.07))

                // Valet — AI assistant chat
                menuItem(
                    icon: "bubble.left.and.text.bubble.right",
                    label: "Valet",
                    tint: gold
                ) {
                    onChat()
                    dismiss()
                }

                Divider().background(Color.white.opacity(0.07))

                // Generate / Regenerate Captions
                menuItem(
                    icon: isGenerating ? "ellipsis" : "sparkles",
                    label: isGenerating ? "Generating…" : (hasCaptions ? "Regenerate Captions" : "Generate Captions"),
                    tint: photosEmpty ? .gray : gold,
                    disabled: photosEmpty || isGenerating
                ) {
                    onCaptions()
                    dismiss()
                }

                Divider().background(Color.white.opacity(0.07))

                // Send to Instagram (iOS-only shortcut)
                menuItem(
                    icon: "camera.on.rectangle",
                    label: "Send to Instagram",
                    tint: Color(red: 0.83, green: 0.34, blue: 0.65),
                    disabled: photosEmpty
                ) {
                    onInstagram()
                    dismiss()
                }

                Divider().background(Color.white.opacity(0.07))

                // Export / Share
                menuItem(
                    icon: "square.and.arrow.up",
                    label: "Export / Share",
                    tint: .white,
                    disabled: photosEmpty
                ) {
                    onShare()
                    dismiss()
                }

                Divider().background(Color.white.opacity(0.07))

                // Preview in 3D — Motion Library pick (Cult UI three-d-carousel)
                menuItem(
                    icon: "cube",
                    label: "Preview in 3D",
                    tint: .white,
                    disabled: photosEmpty
                ) {
                    onPreview3D()
                    dismiss()
                }

                Divider().background(Color.white.opacity(0.07))

                // Archive / Unarchive
                menuItem(
                    icon: dump.archived ? "tray.and.arrow.up" : "archivebox",
                    label: dump.archived ? "Unarchive Dump" : "Archive Dump",
                    tint: .white
                ) {
                    onArchive()
                    dismiss()
                }

                Divider().background(Color.white.opacity(0.07))

                // Delete
                menuItem(icon: "trash", label: "Delete Dump", tint: .red) {
                    onDelete()
                    dismiss()
                }

                Spacer().frame(height: 32)
            }
        }
        .presentationDetents([.height(620)])
        .presentationDragIndicator(.hidden)
    }

    // Thumbs up / down row — same semantics as web: up toggles; down toggles,
    // and rating down opens the Valet chat to ask why.
    private var rateRow: some View {
        HStack(spacing: 12) {
            Text("RATE THIS DUMP")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1)
                .foregroundColor(.white.opacity(0.5))
            Spacer()
            rateButton(kind: "up", systemName: "hand.thumbsup", active: Color(red: 0.29, green: 0.87, blue: 0.5)) {
                onRate(dump.rating == "up" ? nil : "up")
            }
            rateButton(kind: "down", systemName: "hand.thumbsdown", active: .red) {
                if dump.rating == "down" {
                    onRate(nil)
                } else {
                    onRate("down")
                    dismiss()
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private func rateButton(kind: String, systemName: String, active: Color, action: @escaping () -> Void) -> some View {
        let isOn = dump.rating == kind
        return Button(action: action) {
            Image(systemName: isOn ? systemName + ".fill" : systemName)
                .font(.system(size: 15))
                .foregroundColor(isOn ? active : .white.opacity(0.55))
                .frame(width: 44, height: 38)
                .background(isOn ? active.opacity(0.15) : Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isOn ? active.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1)
                )
        }
    }

    private func menuItem(icon: String, label: String, tint: Color, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(disabled ? tint.opacity(0.3) : tint)
                    .frame(width: 24)
                Text(label)
                    .font(.system(size: 16))
                    .foregroundColor(disabled ? .white.opacity(0.25) : .white)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .disabled(disabled)
    }
}
