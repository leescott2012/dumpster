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

        // Default: hide photos already used in a dump.
        // Only show used photos when the "Used" filter is explicitly active.
        if appState.activeFilters.contains(.used) {
            result = result.filter { usedPhotoIDs.contains($0.id) }
        } else {
            result = result.filter { !usedPhotoIDs.contains($0.id) }
        }

        for filter in appState.activeFilters {
            switch filter {
            case .all:     break
            case .starred: result = result.filter { $0.starred }
            case .huji:    result = result.filter { $0.isHuji }
            case .used:    break // already handled above
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
        VStack(alignment: .leading, spacing: 12) {
            heroHeader
            filterPills
            actionRow
            if showSearchField { searchField }
            if appState.addingToDumpId != nil { selectionBanner }
            grid
        }
        .background(Theme.bg(appState.colorMode, cs).ignoresSafeArea())
        .onChange(of: pickerItems) { _, newItems in
            Task { await importPickedPhotos(newItems) }
        }
    }

    // MARK: - Hero header

    @State private var showPoolMenu = false

    private var unusedCount: Int { allPhotos.count - usedPhotoIDs.count }

    private var heroHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Photo Pool")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Theme.text(appState.colorMode, cs))
                    .tracking(-0.4)
                Text("\(unusedCount) available · \(usedPhotoIDs.count) in dumps")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.text2(appState.colorMode, cs))
            }
            Spacer()
            // Pool menu
            Button { showPoolMenu = true } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.text(appState.colorMode, cs))
                    .frame(width: 32, height: 32)
                    .background(Theme.bg2(appState.colorMode, cs))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .confirmationDialog("Photo Pool", isPresented: $showPoolMenu) {
                Button("Sort by Newest") { /* default sort */ }
                Button("Show Used Photos") { appState.activeFilters = [.used] }
                Button("Show Starred") { appState.activeFilters = [.starred] }
                Button("Show All") { appState.activeFilters.removeAll() }
                Button("Cancel", role: .cancel) {}
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 4)
    }

    // MARK: - Filter pills (All / Starred / Huji Only)

    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                pillButton(
                    label: "All",
                    icon: nil,
                    isSelected: appState.activeFilters.isEmpty
                ) {
                    appState.activeFilters.removeAll()
                }
                pillButton(
                    label: "Starred",
                    icon: "star.fill",
                    isSelected: appState.activeFilters.contains(.starred)
                ) {
                    toggleFilter(.starred)
                }
                pillButton(
                    label: "Used",
                    icon: nil,
                    isSelected: appState.activeFilters.contains(.used)
                ) {
                    toggleFilter(.used)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private func pillButton(label: String, icon: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 10, weight: .semibold)) }
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(isSelected ? .black : Theme.text(appState.colorMode, cs))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(isSelected ? Theme.gold : Theme.bg2(appState.colorMode, cs))
            .clipShape(Capsule())
        }
    }

    private func toggleFilter(_ filter: FilterType) {
        if appState.activeFilters.contains(filter) {
            appState.activeFilters.remove(filter)
        } else {
            appState.activeFilters.insert(filter)
        }
    }

    // MARK: - Action row (search + size buttons)

    private var actionRow: some View {
        HStack(spacing: 8) {
            Spacer()
            Button { showSearchField.toggle() } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.text(appState.colorMode, cs))
                    .frame(width: 30, height: 30)
                    .background(Theme.bg2(appState.colorMode, cs))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            sizeButton(symbol: "plus", action: incrementSize)
            sizeButton(symbol: "minus", action: decrementSize)
        }
        .padding(.horizontal, 14)
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
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(filteredPhotos, id: \.id) { photo in
                    GeometryReader { geo in
                        PhotoCardView(
                            photo: photo,
                            context: .pool,
                            isSelected: selectedPhotoIDs.contains(photo.id),
                            isUsed: usedPhotoIDs.contains(photo.id) && !appState.activeFilters.contains(.used),
                            size: CGSize(width: geo.size.width, height: geo.size.width * 1.25),
                            onTap: { tapPoolPhoto(photo) },
                            onToggleStar: { photo.starred.toggle(); try? modelContext.save() },
                            onDelete: { deleteFromPool(photo) }
                        )
                    }
                    .aspectRatio(0.8, contentMode: .fit)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                uploadCard
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 40)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: filteredPhotos.map { $0.id })
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

    /// Permanently delete a photo: remove from all dumps, delete file, delete record.
    private func deleteFromPool(_ photo: DumpPhoto) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            // Remove from any dump that references it
            for dump in allDumps {
                dump.photoIDs.removeAll { $0 == photo.id }
            }
            // Delete the image file from disk
            PhotoStorageManager.shared.deleteImage(relativePath: photo.localPath)
            // Delete the SwiftData record
            modelContext.delete(photo)
            try? modelContext.save()
        }
    }

    // MARK: - Upload card

    private var uploadCard: some View {
        // Use GeometryReader so the card matches photo tile dimensions exactly
        GeometryReader { geo in
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 50, matching: .images) {
                VStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Add Photos")
                        .font(.system(size: 8, weight: .medium))
                }
                .foregroundColor(Theme.text2(appState.colorMode, cs))
                .frame(width: geo.size.width, height: geo.size.width * 1.25)
                .background(Theme.bg2(appState.colorMode, cs))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Theme.border(appState.colorMode, cs),
                                      style: StrokeStyle(lineWidth: 1, dash: [4]))
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .aspectRatio(0.8, contentMode: .fit)
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
