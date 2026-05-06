import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PhotosUI

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

struct DumpCardView: View {

    let dump: PhotoDump
    let isActive: Bool
    let allPhotos: [DumpPhoto]
    let tasteExamples: [AITasteExample]

    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var cs

    @State private var editingTitle = false
    @State private var titleDraft = ""
    @State private var showDeleteConfirm = false
    @State private var captionResult: LLMService.CaptionResult?
    @State private var isGenerating = false
    @State private var captionError: String?
    @State private var showDumpMenu = false
    @State private var draggingPhotoId: String? = nil
    @State private var dumpPickerItems: [PhotosPickerItem] = []

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
                    isActive ? appState.accentColor : Theme.border(appState.colorMode, cs),
                    lineWidth: isActive ? 2 : 1
                )
        )
        .padding(.horizontal, 12)
        .sheet(isPresented: $showDumpMenu) {
            DumpMenuSheet(
                dump: dump,
                isGenerating: isGenerating,
                photosEmpty: photos.isEmpty,
                onCaptions: { Task { await generateCaptions() } },
                onShare: shareDump,
                onDelete: { showDeleteConfirm = true },
                onHeart: { recordTasteExample(positive: true) }
            )
        }
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
            HStack(spacing: 8) {
                Text("DUMP \(String(format: "%02d", dump.num))")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(2.0)
                    .foregroundColor(appState.accentColor)

                if dump.vibeBadge == "mismatch" {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.yellow)
                }

                if dump.isAIGenerated {
                    Text("AI")
                        .font(.system(size: 8, weight: .black))
                        .tracking(1.0)
                        .foregroundColor(.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(appState.accentColor)
                        .clipShape(Capsule())
                }

                Spacer()

                Button { showDumpMenu = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Theme.text2(appState.colorMode, cs))
                        .frame(width: 28, height: 28)
                        .background(Theme.bg2(appState.colorMode, cs))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

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
                    .foregroundColor(appState.accentColor)
                    .frame(width: 20, height: 20)
                    .background(appState.accentColor.opacity(0.15))
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
                        onRemoveFromDump: { removePhoto(photo) }
                    )
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
                    if photos.isEmpty {
                        // Empty dump → show two clear options
                        fromPoolCard
                        fromLibraryCard
                    } else {
                        addPhotosCard
                    }
                }
            }
            .padding(.horizontal, 14)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: dump.photoIDs)
    }

    /// "Pick from Pool" — animates a scroll down to the photo pool with this dump in selection mode
    @ViewBuilder
    private var fromPoolCard: some View {
        let accent = appState.accentColor
        let text3  = Theme.text3(appState.colorMode, cs)
        Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                appState.addingToDumpId = dump.id
                appState.activePoolTab = .photos
                appState.scrollToPool = UUID()
            }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "square.stack.3d.down.right")
                    .font(.system(size: 24, weight: .semibold))
                Text("From Pool")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.6)
                Text("Pick photos already imported")
                    .font(.system(size: 9))
                    .foregroundColor(text3)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 8)
            }
            .foregroundColor(accent)
            .frame(width: 145, height: 195)
            .background(accent.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(accent.opacity(0.45), lineWidth: 1.2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    /// "From Library" — opens iOS PhotosPicker; imports straight into this dump
    @ViewBuilder
    private var fromLibraryCard: some View {
        let bg2    = Theme.bg2(appState.colorMode, cs)
        let text2  = Theme.text2(appState.colorMode, cs)
        let text3  = Theme.text3(appState.colorMode, cs)
        let border = Theme.border(appState.colorMode, cs)
        PhotosPicker(
            selection: $dumpPickerItems,
            maxSelectionCount: 20,
            selectionBehavior: .ordered,
            matching: .images
        ) {
            VStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 24, weight: .semibold))
                Text("From Library")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.6)
                Text("Import new photos from iOS Photos")
                    .font(.system(size: 9))
                    .foregroundColor(text3)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 8)
            }
            .foregroundColor(text2)
            .frame(width: 145, height: 195)
            .background(bg2)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(border, style: StrokeStyle(lineWidth: 1, dash: [4]))
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .onChange(of: dumpPickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPickedItems(items) }
        }
    }

    /// Compact "+" card shown once a dump already has photos
    @ViewBuilder
    private var addPhotosCard: some View {
        let bg2    = Theme.bg2(appState.colorMode, cs)
        let text2  = Theme.text2(appState.colorMode, cs)
        let border = Theme.border(appState.colorMode, cs)
        PhotosPicker(
            selection: $dumpPickerItems,
            maxSelectionCount: 20,
            selectionBehavior: .ordered,
            matching: .images
        ) {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                Text("Add Photos")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(text2)
            .frame(width: 145, height: 195)
            .background(bg2)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(border, style: StrokeStyle(lineWidth: 1, dash: [4]))
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .onChange(of: dumpPickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPickedItems(items) }
        }
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        let count = photos.count
        let isPeak = count >= 10 && count <= 12
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.bg3(appState.colorMode, cs))
                    .frame(height: 3)
                RoundedRectangle(cornerRadius: 2)
                    .fill(isPeak ? appState.accentColor : Color.white.opacity(0.4))
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
                    .background(appState.accentColor)
                    .cornerRadius(3)
            }
            if dump.liked {
                Image(systemName: "heart.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.red.opacity(0.8))
            }
            Spacer()
            if let err = captionError {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.removeText)
                    .lineLimit(1)
            } else if isGenerating {
                ProgressView().scaleEffect(0.7).tint(appState.accentColor)
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

        let taste = AITasteExample.promptBlock(from: tasteExamples)

        do {
            let result = try await LLMService.shared.generateCaption(
                for: dump.title,
                category: topCategory,
                tasteBlock: taste
            )
            withAnimation(.spring()) { captionResult = result }
        } catch {
            captionError = error.localizedDescription
            CrashReporter.shared.capture(error, tags: ["op": "caption_generate", "dumpId": dump.id])
        }
    }

    /// Record this dump as a taste signal (positive = loved, negative = disliked).
    @MainActor
    private func importPickedItems(_ items: [PhotosPickerItem]) async {
        var newPhotoIDs: [String] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else { continue }
            let filename = UUID().uuidString + ".jpg"
            let localPath = PhotoStorageManager.shared.saveImage(uiImage, filename: filename)
            let photo = DumpPhoto(localPath: localPath, filename: filename)
            modelContext.insert(photo)
            newPhotoIDs.append(photo.id)
        }
        if !newPhotoIDs.isEmpty {
            dump.photoIDs.append(contentsOf: newPhotoIDs)
            try? modelContext.save()
        }
        dumpPickerItems.removeAll()
    }

    private func recordTasteExample(positive: Bool) {
        let example = AITasteExample.from(dump: dump, photos: photos, isPositive: positive)
        modelContext.insert(example)
        if positive {
            dump.liked = true
        }
        try? modelContext.save()
    }
}
