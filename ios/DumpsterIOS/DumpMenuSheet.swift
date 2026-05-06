import SwiftUI

// MARK: - DumpMenuSheet
//
// Bottom sheet presented when the user taps the "..." button on a DumpCardView.
// Provides quick actions: generate captions, share, delete, and heart (taste signal).

struct DumpMenuSheet: View {
    let dump: PhotoDump
    let isGenerating: Bool
    let photosEmpty: Bool
    let onCaptions: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void
    let onHeart: () -> Void

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
                    .padding(.bottom, 20)

                // Generate Captions
                menuItem(
                    icon: isGenerating ? "ellipsis" : "sparkles",
                    label: isGenerating ? "Generating…" : "Generate Captions",
                    tint: photosEmpty ? .gray : gold,
                    disabled: photosEmpty || isGenerating
                ) {
                    onCaptions()
                    dismiss()
                }

                Divider().background(Color.white.opacity(0.07))

                // Heart — only for AI-generated dumps
                if dump.isAIGenerated {
                    menuItem(
                        icon: dump.liked ? "heart.fill" : "heart",
                        label: dump.liked ? "Loved (in taste memory)" : "Love this dump",
                        tint: dump.liked ? .red : .white
                    ) {
                        onHeart()
                        dismiss()
                    }
                    Divider().background(Color.white.opacity(0.07))
                }

                // Share
                menuItem(icon: "square.and.arrow.up", label: "Share Dump", tint: .white) {
                    onShare()
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
        .presentationDetents([dump.isAIGenerated ? .height(320) : .height(260)])
        .presentationDragIndicator(.hidden)
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
