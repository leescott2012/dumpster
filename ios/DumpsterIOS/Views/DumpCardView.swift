import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Drop delegate for reordering photos within a dump

struct DumpPhotoDropDelegate: DropDelegate {
    let targetId: String
    let dump: PhotoDump
    @Binding var draggingId: String?
    let modelContext: ModelContext

    func dropEntered(info: DropInfo) {
        guard let from = draggingId,
              from != targetId,
              let fromIdx = dump.photoIDs.firstIndex(of: from),
              let toIdx   = dump.photoIDs.firstIndex(of: targetId) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            dump.photoIDs.move(
                fromOffsets: IndexSet(integer: fromIdx),
                toOffset: toIdx > fromIdx ? toIdx + 1 : toIdx
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingId = nil
        try? modelContext.save()
        return true
    }
}

// MARK: - DumpCardView

/// A single PhotoDump rendered as a card with header, horizontal photo carousel,
/// progress bar footer, and action buttons (like, share, delete, generate captions).
struct DumpCardView: View {

    let dump: PhotoDump
    let isActive: Bool

    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var cs

    @Query private var allPhotos: [DumpPhoto]

    @State private var editingTitle = false
    @State private var titleDraft = ""
    @State private var showDeleteConfirm = false
    @State private var captionResult: LLMService.CaptionResult?
    @State private var isGenerating = false
    @State private var captionError: String?

    /// For drag-to-reorder within the carousel
    @State private var draggingPhotoId: String? = nil

    /// Resolve the dump's photo IDs in order.
    private var photos: [DumpPhoto] {
        let byID = Dictionary(uniqueKeysWithValues: allPhotos.map { ($0.id, $0) })
        return dump.photoIDs.compactMap { byID[$0] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            tagBreadcrumb
            carousel
            progressBar
            actionRow
        }
        .padding(.vertical, 14)
        .background(Theme.bg1(appState.colorMode, cs))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isActive ? Theme.gold : Theme.border(appState.colorMode, cs),
                    lineWidth: isActive ? 2 : 1
                )
        )
        .padding(.horizontal, 12)
        .confirmationDialog("Delete this dump?", isPresented: $showDeleteConfirm) {
            Button("Delete Dump", role: .destructive) { deleteDump() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Photos will remain in your pool.")
        }
        .overlay(alignment: .bottom) {
            if let result = captionResult {
                DumpCaptionBubble(
                    result: result,
                    onDismiss: { withAnimation { captionResult = nil } },
                    onSaveCaption: { text in
                        let cap = DumpCaption(text: text, style: "ai", dumpId: dump.id)
                        modelContext.insert(cap)
                        try? modelContext.save()
                    }
                )
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Row 1: small "DUMP 01" tracked label  |  action icons
            HStack(spacing: 8) {
                Text("DUMP \(String(format: "%02d", dump.num))")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(2.0)
                    .foregroundColor(Theme.gold)

                if dump.vibeBadge == "mismatch" {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.yellow)
                }

                Spacer()

                iconButton(symbol: dump.liked ? "heart.fill" : "heart",
                           tint: dump.liked ? .red : nil) {
                    dump.liked.toggle()
                    try? modelContext.save()
                }
                iconButton(symbol: "sparkles", tint: isGenerating ? Theme.text3(appState.colorMode, cs) : Theme.gold) {
                    Task { await generateCaptions() }
                }
                .disabled(isGenerating || photos.isEmpty)
                iconButton(symbol: "square.and.arrow.up") { shareDump() }
                iconButton(symbol: "trash", tint: Theme.removeText) { showDeleteConfirm = true }
            }

            // Row 2: BIG title on its own line
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                titleView
                if dump.titleApproved == nil {
                    approveButtons
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private var titleView: some View {
        if editingTitle {
            TextField("Dump title", text: $titleDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Theme.text(appState.colorMode, cs))
                .tracking(-0.3)
                .submitLabel(.done)
                .onSubmit { commitTitle() }
        } else {
            Text(dump.title)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Theme.text(appState.colorMode, cs))
                .tracking(-0.3)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .onTapGesture {
                    titleDraft = dump.title
                    editingTitle = true
                }
        }
    }

    private var approveButtons: some View {
        HStack(spacing: 4) {
            Button {
                dump.titleApproved = true
                try? modelContext.save()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Theme.gold)
                    .frame(width: 20, height: 20)
                    .background(Theme.goldDim)
                    .clipShape(Circle())
            }
            Button {
                dump.titleApproved = false
                dump.title = FormulaEngine.generateDumpTitle(for: photos)
                try? modelContext.save()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Theme.text2(appState.colorMode, cs))
                    .frame(width: 20, height: 20)
                    .background(Theme.bg2(appState.colorMode, cs))
                    .clipShape(Circle())
            }
        }
    }

    private func iconButton(symbol: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundColor(tint ?? Theme.text2(appState.colorMode, cs))
                .frame(width: 28, height: 28)
                .background(Theme.bg2(appState.colorMode, cs))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func commitTitle() {
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            dump.title = trimmed
            dump.titleApproved = true
            try? modelContext.save()
        }
        editingTitle = false
    }

    // MARK: - Tag breadcrumb

    private var tagBreadcrumb: some View {
        HStack(spacing: 6) {
            Text(uniqueCategories.joined(separator: " / "))
                .font(.system(size: 11))
                .foregroundColor(Theme.text2(appState.colorMode, cs))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(photos.count)/20 photos")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.text3(appState.colorMode, cs))
        }
        .padding(.horizontal, 14)
    }

    private var uniqueCategories: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for p in photos {
            let cap = p.category.capitalized
            if !cap.isEmpty && !seen.contains(cap) {
                seen.insert(cap)
                ordered.append(cap)
            }
        }
        return Array(ordered.prefix(5))
    }

    // MARK: - Carousel (with drag-to-reorder)

    private var carousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    PhotoCardView(
                        photo: photo,
                        context: .dump(dumpId: dump.id),
                        slotIndex: index,
                        totalInDump: photos.count,
                        size: CGSize(width: 145, height: 195),
                        onRemoveFromDump: { removePhoto(photo) },
                        onToggleStar: { photo.starred.toggle(); try? modelContext.save() }
                    )
                    // Drag to reorder
                    .onDrag {
                        draggingPhotoId = photo.id
                        return NSItemProvider(object: photo.id as NSString)
                    }
                    .onDrop(
                        of: [UTType.plainText],
                        delegate: DumpPhotoDropDelegate(
                            targetId: photo.id,
                            dump: dump,
                            draggingId: $draggingPhotoId,
                            modelContext: modelContext
                        )
                    )
                    .opacity(draggingPhotoId == photo.id ? 0.5 : 1.0)
                }
                if photos.count < 20 {
                    addPhotosCard
                }
            }
            .padding(.horizontal, 14)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: dump.photoIDs)
    }

    private var addPhotosCard: some View {
        Button {
            appState.addingToDumpId = dump.id
            appState.activePoolTab = .photos
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                Text("Add Photos")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(Theme.text2(appState.colorMode, cs))
            .frame(width: 145, height: 195)
            .background(Theme.bg2(appState.colorMode, cs))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.border(appState.colorMode, cs),
                                  style: StrokeStyle(lineWidth: 1, dash: [4]))
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Progress

    private var progressBar: some View {
        let count = photos.count
        let isPeak = count >= 10 && count <= 12
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.bg3(appState.colorMode, cs))
                    .frame(height: 3)
                RoundedRectangle(cornerRadius: 2)
                    .fill(isPeak ? Theme.gold : Color.white.opacity(0.4))
                    .frame(width: geo.size.width * min(1.0, CGFloat(count) / 20.0), height: 3)
            }
        }
        .frame(height: 3)
        .padding(.horizontal, 14)
    }

    // MARK: - Action row

    private var actionRow: some View {
        HStack(spacing: 6) {
            Text("\(photos.count)/20")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(Theme.text3(appState.colorMode, cs))
            if photos.count >= 10 && photos.count <= 12 {
                Text("PEAK")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundColor(.black)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Theme.gold)
                    .cornerRadius(3)
            }
            Spacer()
            if let err = captionError {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.removeText)
                    .lineLimit(1)
            } else if isGenerating {
                ProgressView().scaleEffect(0.7).tint(Theme.gold)
            }
        }
        .padding(.horizontal, 14)
    }

    // MARK: - Actions

    private func removePhoto(_ photo: DumpPhoto) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            dump.photoIDs.removeAll { $0 == photo.id }
        }
        try? modelContext.save()
    }

    private func deleteDump() {
        modelContext.delete(dump)
        try? modelContext.save()
    }

    private func shareDump() {
        let images: [UIImage] = photos.compactMap {
            PhotoStorageManager.shared.loadImage(relativePath: $0.localPath)
        }
        guard !images.isEmpty else { return }
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        let av = UIActivityViewController(activityItems: images, applicationActivities: nil)
        av.popoverPresentationController?.sourceView = root.view
        root.present(av, animated: true)
    }

    @MainActor
    private func generateCaptions() async {
        guard !photos.isEmpty else { return }
        captionError = nil
        isGenerating = true
        defer { isGenerating = false }

        let topCategory = photos
            .map { $0.category.uppercased() }
            .reduce(into: [String: Int]()) { acc, c in acc[c, default: 0] += 1 }
            .max { $0.value < $1.value }?.key ?? "LIFESTYLE"
        let labels = Array(Set(photos.flatMap { $0.labels })).prefix(20).map { $0 }

        let req = LLMService.CaptionRequest(
            dumpTitle: dump.title,
            category: topCategory,
            labels: labels,
            photoCount: photos.count
        )
        do {
            let result = try await LLMService.shared.generateCaptions(for: req)
            withAnimation(.spring()) { captionResult = result }
        } catch {
            captionError = error.localizedDescription
        }
    }
}
