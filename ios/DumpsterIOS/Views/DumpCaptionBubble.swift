import SwiftUI

/// Floating caption-results overlay anchored to a dump card.
/// Shows up to 10 caption options after `LLMService.generateCaptions`.
/// Tap a caption to copy; tap backdrop or swipe down to dismiss.
struct DumpCaptionBubble: View {

    let result: LLMService.CaptionResult
    let onDismiss: () -> Void
    let onSaveCaption: ((String) -> Void)?

    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var cs
    @State private var copiedIndex: Int?
    @State private var dragY: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                Spacer()
                bubble
                    .offset(y: max(0, dragY))
                    .gesture(
                        DragGesture()
                            .onChanged { dragY = $0.translation.height }
                            .onEnded { v in
                                if v.translation.height > 80 { onDismiss() }
                                else { withAnimation(.spring()) { dragY = 0 } }
                            }
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 24)
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Grab handle
            HStack {
                Spacer()
                Capsule()
                    .fill(Theme.text3(appState.colorMode, cs))
                    .frame(width: 40, height: 4)
                Spacer()
            }
            .padding(.top, 8)
            .padding(.bottom, 12)

            // Header
            HStack {
                Text(result.dumpTitle.uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.5)
                    .foregroundColor(appState.accentColor)
                Spacer()
                Text(result.vibe)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.text2(appState.colorMode, cs))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Divider()
                .background(Theme.border(appState.colorMode, cs))

            // Captions list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(result.captions.enumerated()), id: \.offset) { idx, caption in
                        captionRow(idx: idx, text: caption)
                        if idx < result.captions.count - 1 {
                            Divider().background(Theme.border(appState.colorMode, cs).opacity(0.4))
                        }
                    }
                }
            }
            .frame(maxHeight: 380)
        }
        .background(Theme.bg1(appState.colorMode, cs))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Theme.border(appState.colorMode, cs), lineWidth: 1)
        )
    }

    private func captionRow(idx: Int, text: String) -> some View {
        Button {
            UIPasteboard.general.string = text
            onSaveCaption?(text)
            withAnimation(.easeOut(duration: 0.15)) { copiedIndex = idx }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                if copiedIndex == idx { copiedIndex = nil }
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text("\(idx + 1)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(appState.accentColor)
                    .frame(width: 18, alignment: .leading)
                Text(text)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.text(appState.colorMode, cs))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if copiedIndex == idx {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(appState.accentColor)
                } else {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.text3(appState.colorMode, cs))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
    }
}
