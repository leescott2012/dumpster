import SwiftUI
import SwiftData

/// Swap ONE dump photo for a pool photo (mirrors web client/src/components/RecycleSheet.tsx).
/// Choose: Manual Pick (tap a pool photo to swap) or Let AI Choose (Valet picks, you confirm).
/// The AI pick rides the same /api/ai-chat path as the Valet, so the server charges it exactly
/// like a Valet message (1 credit) and refunds on failure. Undo = the header undo (one snapshot per swap).
struct RecycleSheet: View {

    let dump: PhotoDump
    let photo: DumpPhoto            // the dump photo being replaced
    let allPhotos: [DumpPhoto]
    let tasteExamples: [AITasteExample]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var undoManager: DumpsterUndoManager
    @Query private var dumps: [PhotoDump]

    private enum Phase { case choose, manual, aiLoading, aiDone }

    @State private var phase: Phase = .choose
    @State private var aiPickId: String?
    @State private var aiReason = ""
    @State private var outOfCredits = false

    private let gold = Color(hex: "#C8A96E")
    private let purple = Color(hex: "#A78BFA")
    private let green = Color(hex: "#4ADE80")
    private let red = Color(hex: "#EF4444")

    /// Unused photos (in no dump). Videos are device-only and never go to the AI.
    private var pool: [DumpPhoto] {
        let used = Set(dumps.flatMap { $0.photoIDs })
        return allPhotos.filter { !used.contains($0.id) && !VideoStore.isVideoPath($0.localPath) }
    }

    private var dumpPhotos: [DumpPhoto] {
        let byID = Dictionary(uniqueKeysWithValues: allPhotos.map { ($0.id, $0) })
        return dump.photoIDs.compactMap { byID[$0] }
    }

    private var creditLabel: String {
        LLMService.shared.hasAnyAPIKey ? "" : " · \(CreditManager.Cost.aiChat) credit"
    }

    var body: some View {
        ZStack {
            Color(white: 0.055).ignoresSafeArea()
            VStack(spacing: 0) {
                Capsule().fill(Color.white.opacity(0.2)).frame(width: 36, height: 4)
                    .padding(.top, 12).padding(.bottom, 8)
                header
                Divider().background(Color.white.opacity(0.07))
                ScrollView {
                    Group {
                        switch phase {
                        case .choose: chooseView
                        case .manual: manualView
                        case .aiLoading: loadingView
                        case .aiDone: doneView
                        }
                    }
                    .padding(.horizontal, 24).padding(.vertical, 20)
                }
            }
        }
        .presentationDetents([.fraction(0.8), .large])
        .presentationDragIndicator(.hidden)
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            thumb(photo, size: 40, corner: 8)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(red, lineWidth: 2))
            VStack(alignment: .leading, spacing: 1) {
                Text("♻️ Recycle Photo")
                    .font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                Text("\(photo.category) · \(dump.title)")
                    .font(.system(size: 11)).foregroundColor(Color(white: 0.35)).lineLimit(1)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(white: 0.5))
                    .frame(width: 32, height: 32)
                    .background(Color(white: 0.1)).clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color(white: 0.17), lineWidth: 1))
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
    }

    // MARK: - Phases

    private var chooseView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Swap this photo for something from your pool. Pick yourself or let AI find the best fit.")
                .font(.system(size: 13)).foregroundColor(Color(white: 0.6)).lineSpacing(4)
                .padding(.bottom, 8)
            optionRow(icon: "hand.tap", tint: appState.accentColor, title: "Manual Pick",
                      subtitle: "Browse the pool and choose") { phase = .manual }
            optionRow(icon: "sparkles", tint: purple, title: "Let AI Choose",
                      subtitle: pool.isEmpty ? "Pool is empty" : "Best fit based on the dump's vibe\(creditLabel)") {
                Task { await aiPick() }
            }
            .disabled(pool.isEmpty).opacity(pool.isEmpty ? 0.4 : 1)
        }
    }

    private func optionRow(icon: String, tint: Color, title: String, subtitle: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16)).foregroundColor(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tint.opacity(0.25), lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .bold)).foregroundColor(Color(white: 0.91))
                    Text(subtitle).font(.system(size: 11)).foregroundColor(Color(white: 0.54))
                }
                Spacer()
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
            .background(Color(white: 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(white: 0.17), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var manualView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tap a photo to swap it in · \(pool.count) available")
                .font(.system(size: 12)).foregroundColor(Color(white: 0.54))
            if pool.isEmpty {
                Text("Pool is empty")
                    .font(.system(size: 13)).foregroundColor(Color(white: 0.27))
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                ForEach(pool, id: \.id) { p in
                    Button { swap(to: p.id) } label: {
                        ZStack(alignment: .bottom) {
                            thumb(p, size: nil, corner: 8)
                            Text(p.category)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white.opacity(0.7))
                                .frame(maxWidth: .infinity)
                                .padding(.top, 16).padding(.bottom, 4)
                                .background(LinearGradient(colors: [.clear, .black.opacity(0.7)],
                                                           startPoint: .top, endPoint: .bottom))
                        }
                        .aspectRatio(3.0 / 4.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(white: 0.17), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView().tint(purple).scaleEffect(1.2)
            Text("Finding the best swap...")
                .font(.system(size: 14, weight: .semibold)).foregroundColor(Color(white: 0.91))
            Text("Analyzing your dump's vibe and pool")
                .font(.system(size: 12)).foregroundColor(Color(white: 0.35))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 48)
    }

    private var doneView: some View {
        let pick = pool.first { $0.id == aiPickId }
        return VStack(spacing: 16) {
            Text(aiReason)
                .font(.system(size: 13)).foregroundColor(Color(white: 0.8)).lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(Color(white: 0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(white: 0.17), lineWidth: 1))

            if let pick {
                HStack(spacing: 12) {
                    beforeAfter(photo, label: "OUT", tint: red)
                    Text("→").font(.system(size: 20)).foregroundColor(Color(white: 0.54))
                    beforeAfter(pick, label: "IN", tint: green)
                }
            }

            HStack(spacing: 10) {
                if let pick {
                    Button { swap(to: pick.id) } label: {
                        Label("Swap It", systemImage: "checkmark")
                            .font(.system(size: 14, weight: .bold)).foregroundColor(.black)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(green).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                if outOfCredits {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            CreditManager.shared.showOutOfCredits = true
                        }
                    } label: {
                        Text("Get credits")
                            .font(.system(size: 14, weight: .bold)).foregroundColor(.black)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(appState.accentColor).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                Button { phase = .manual } label: {
                    Text("Pick Myself")
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(Color(white: 0.6))
                        .frame(maxWidth: pick == nil && !outOfCredits ? .infinity : nil)
                        .padding(.horizontal, 20).padding(.vertical, 14)
                        .background(Color(white: 0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(white: 0.17), lineWidth: 1))
                }
            }
        }
    }

    private func beforeAfter(_ p: DumpPhoto, label: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            thumb(p, size: nil, corner: 8)
                .frame(width: 80, height: 100)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tint, lineWidth: 2))
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundColor(tint)
        }
    }

    private func thumb(_ p: DumpPhoto, size: CGFloat?, corner: CGFloat) -> some View {
        Group {
            if let img = PhotoStorageManager.shared.thumbnail(relativePath: p.localPath, maxPixel: 300) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Rectangle().fill(Color(white: 0.12))
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: corner))
    }

    // MARK: - Logic

    /// Replace `photo` in its own slot with `newId`; the old photo drops back to the pool by itself.
    private func swap(to newId: String) {
        guard let idx = dump.photoIDs.firstIndex(of: photo.id), !dump.photoIDs.contains(newId) else {
            dismiss(); return
        }
        undoManager.pushSnapshot(photos: allPhotos, dumps: dumps)
        dump.photoIDs[idx] = newId
        try? modelContext.save()
        HapticManager.shared.playTick()
        appState.showStatus("Photo swapped. Tap undo in the top bar to revert.")
        dismiss()
    }

    @MainActor
    private func aiPick() async {
        guard !pool.isEmpty, let idx = dump.photoIDs.firstIndex(of: photo.id) else { return }
        phase = .aiLoading
        outOfCredits = false
        do {
            func chat(_ p: DumpPhoto) -> LLMService.ChatPhoto {
                LLMService.ChatPhoto(id: p.id, category: p.category, labels: p.promptLabels)
            }
            let taste = AITasteExample.promptBlock(from: tasteExamples) + AITasteExample.captionVoiceBlock()
            let alt = photo.promptLabels.prefix(3).joined(separator: ", ")
            let response = try await LLMService.shared.chatWithDump(
                dumpTitle: dump.title,
                dumpPhotos: dumpPhotos.map(chat),
                poolPhotos: pool.map(chat),
                history: [],
                message: "I want to recycle (swap out) the photo [\(photo.id)] (\(photo.category) — \(alt)) from this dump. It sits at index \(idx) (0-based). Pick the BEST replacement from the pool that fits the dump's overall vibe and flow. Respond with a swap_out action for index \(idx) and a swap_in action for your pick. Explain briefly why this replacement works better.",
                vibe: dump.vibeBadge,
                tasteBlock: taste
            )
            // Only accept a photo that is really in the pool.
            let poolIDs = Set(pool.map { $0.id })
            aiPickId = response.actions.first { $0.type == "swap_in" && poolIDs.contains($0.photoId ?? "") }?.photoId
            let reply = response.reply
                .replacingOccurrences(of: "\\s*\\[[0-9a-fA-F]{8}-[0-9a-fA-F-]{27,}\\]", with: "", options: .regularExpression)
                .replacingOccurrences(of: "**", with: "")
            aiReason = reply.isEmpty && aiPickId == nil ? "I couldn't find a good replacement. Try picking manually." : reply
        } catch LLMService.LLMError.insufficientCredits {
            CreditManager.shared.showOutOfCredits = false   // we show our own "Get credits" button; the root sheet can't present over this one
            outOfCredits = true
            aiPickId = nil
            aiReason = "You're out of credits for an AI pick. Top up, or pick one yourself."
        } catch {
            aiPickId = nil
            aiReason = FriendlyError.message(for: error, tags: ["op": "ai_recycle", "dumpId": dump.id])
        }
        phase = .aiDone
    }
}
