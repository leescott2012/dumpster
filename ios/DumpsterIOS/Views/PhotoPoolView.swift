import SwiftUI
import SwiftData
import PhotosUI

/// The photo pool grid: header + filter chips + responsive LazyVGrid.
///
/// Phase 4 scope: free-standing view that renders pool of photos from SwiftData.
/// Wire-up to ContentView (replacing WKWebView) happens in Phase 6.
struct PhotoPoolView: View {

    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var cs

    @Query(sort: \DumpPhoto.createdAt, order: .reverse) private var allPhotos: [DumpPhoto]
    @Query private var allDumps: [PhotoDump]

    @State private var showSearchField = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var selectedPhotoIDs: Set<String> = []
    @State private var pinchScale: CGFloat = 1.0

    // MARK: - Derived

    /// IDs already used in any dump → for "used" filter + dimmed state.
    private var usedPhotoIDs: Set<String> {
        Set(allDumps.flatMap { $0.photoIDs })
    }

    private var filteredPhotos: [DumpPhoto] {
        var result = allPhotos

        for filter in appState.activeFilters {
            switch filter {
            case .all:     break
            case .starred: result = result.filter { $0.starred }
            case .huji:    result = result.filter { $0.isHuji }
            case .used:    result = result.filter { usedPhotoIDs.contains($0.id) }
            case .videos:  result = result.filter { isVideo($0.filename) }
            }
        }

        let q = appState.poolSearchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            result = result.filter { p in
                p.filename.lowercased().contains(q) ||
                p.category.lowercased().contains(q) ||
                p.labels.contains { $0.lowercased().contains(q) }
            }
        }
        return result
    }

    private func isVideo(_ filename: String) -> Bool {
        let f = filename.lowercased()
        return f.hasSuffix(".mov") || f.hasSuffix(".mp4") || f.hasSuffix(".m4v")
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if !appState.activeFilters.isEmpty { activeFilterChips }
            if showSearchField { searchField }
            if appState.addingToDumpId != nil { selectionBanner }
            grid
        }
        .background(Theme.bg(appState.colorMode, cs).ignoresSafeArea())
        .onChange(of: pickerItems) { _, newItems in
            Task { await importPickedPhotos(newItems) }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("PHOTO POOL")
                .font(.system(size: 11, weight: .heavy))
                .tracking(2.0)
                .foregroundColor(Theme.gold)
            Spacer()
            PoolFilterMenu()
            Button { showSearchField.toggle() } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.text(appState.colorMode, cs))
                    .frame(width: 32, height: 32)
                    .background(Theme.bg2(appState.colorMode, cs))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            sizeButton(symbol: "plus", action: incrementSize)
            sizeButton(symbol: "minus", action: decrementSize)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private func sizeButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Theme.text2(appState.colorMode, cs))
                .frame(width: 26, height: 26)
                .background(Theme.bg2(appState.colorMode, cs))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func incrementSize() {
        switch appState.poolSize {
        case .small:  appState.poolSize = .medium
        case .medium: appState.poolSize = .large
        case .large:  break
        }
    }

    private func decrementSize() {
        switch appState.poolSize {
        case .large:  appState.poolSize = .medium
        case .medium: appState.poolSize = .small
        case .small:  break
        }
    }

    // MARK: - Filter chips

    private var activeFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(appState.activeFilters), id: \.self) { filter in
                    HStack(spacing: 4) {
                        Text(filter.rawValue.capitalized)
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(Theme.text(appState.colorMode, cs))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.goldDim)
                    .clipShape(Capsule())
                    .onTapGesture { appState.activeFilters.remove(filter) }
                }
            }
            .padding(.horizontal, 12)
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Theme.text3(appState.colorMode, cs))
            TextField("Search labels, category, filename…", text: $appState.poolSearchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundColor(Theme.text(appState.colorMode, cs))
            if !appState.poolSearchQuery.isEmpty {
                Button { appState.poolSearchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.text3(appState.colorMode, cs))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.bg2(appState.colorMode, cs))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
    }

    // MARK: - Selection banner

    private var selectionBanner: some View {
        HStack {
            Text("Select photos to add to dump")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.text(appState.colorMode, cs))
            Spacer()
            Button("Done") { addSelectionToDump() }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.gold)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.goldDim)
    }

    private func addSelectionToDump() {
        guard let dumpId = appState.addingToDumpId,
              let dump = allDumps.first(where: { $0.id == dumpId }) else {
            appState.addingToDumpId = nil
            selectedPhotoIDs.removeAll()
            return
        }
        let toAdd = selectedPhotoIDs.subtracting(dump.photoIDs)
        var newIDs = dump.photoIDs
        for id in toAdd where newIDs.count < 20 { newIDs.append(id) }
        dump.photoIDs = newIDs
        try? modelContext.save()
        selectedPhotoIDs.removeAll()
        appState.addingToDumpId = nil
    }

    // MARK: - Grid

    private var grid: some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 6),
            count: appState.poolSize.columnCount
        )
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(filteredPhotos) { photo in
                    GeometryReader { geo in
                        PhotoCardView(
                            photo: photo,
                            context: .pool,
                            isSelected: selectedPhotoIDs.contains(photo.id),
                            isUsed: usedPhotoIDs.contains(photo.id) && !appState.activeFilters.contains(.used),
                            size: CGSize(width: geo.size.width, height: geo.size.width * 1.25),
                            onTap: { tapPoolPhoto(photo) },
                            onToggleStar: { photo.starred.toggle(); try? modelContext.save() },
                            onToggleHuji: { photo.isHuji.toggle(); try? modelContext.save() }
                        )
                    }
                    .aspectRatio(0.8, contentMode: .fit)
                }
                uploadCard
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 40)
        }
        .gesture(magnificationGesture)
    }

    private func tapPoolPhoto(_ photo: DumpPhoto) {
        guard appState.addingToDumpId != nil else { return }
        if selectedPhotoIDs.contains(photo.id) {
            selectedPhotoIDs.remove(photo.id)
        } else {
            selectedPhotoIDs.insert(photo.id)
        }
    }

    // MARK: - Upload card

    private var uploadCard: some View {
        PhotosPicker(selection: $pickerItems, maxSelectionCount: 50, matching: .images) {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                Text("Add Photos")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(Theme.text2(appState.colorMode, cs))
            .frame(maxWidth: .infinity)
            .aspectRatio(0.8, contentMode: .fit)
            .background(Theme.bg2(appState.colorMode, cs))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.border(appState.colorMode, cs),
                                  style: StrokeStyle(lineWidth: 1, dash: [4]))
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func importPickedPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let relPath = PhotoStorageManager.shared.saveImageData(data) else { continue }
            let filename = (relPath as NSString).lastPathComponent
            let category = FormulaEngine.guessCategory(filename: filename)
            let isHuji = FormulaEngine.detectHuji(filename: filename)
            let photo = DumpPhoto(
                localPath: relPath,
                filename: filename,
                category: category,
                isHuji: isHuji
            )
            await MainActor.run {
                modelContext.insert(photo)
                try? modelContext.save()
            }
        }
        await MainActor.run { pickerItems.removeAll() }
    }

    // MARK: - Pinch

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { pinchScale = $0 }
            .onEnded { scale in
                if scale > 1.3 { incrementSize() }
                else if scale < 0.7 { decrementSize() }
                pinchScale = 1.0
            }
    }
}
