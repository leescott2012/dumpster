import SwiftUI
import SwiftData
import PhotosUI

/// The photo pool grid: header + filter chips + responsive LazyVGrid.
struct PhotoPoolView: View {

    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var cs

    let allPhotos: [DumpPhoto]
    let allDumps: [PhotoDump]

    @State private var showSearchField = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var selectedPhotoIDs: Set<String> = []
    @State private var pinchScale: CGFloat = 1.0

    // MARK: - Derived

    private var usedPhotoIDs: Set<String> {
        Set(allDumps.flatMap { $0.photoIDs })
    }

    private var filteredPhotos: [DumpPhoto] {
        var result = allPhotos

        if appState.activeFilters.contains(.used) {
            result = result.filter { usedPhotoIDs.contains($0.id) }
        } else {
            result = result.filter { !usedPhotoIDs.contains($0.id) }
        }

        for filter in appState.activeFilters {
            switch filter {
            case .all:    break
            case .huji:   result = result.filter { $0.isHuji }
            case .used:   break
            case .videos: result = result.filter { isVideo($0.filename) }
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

    private var poolIsEmpty: Bool { allPhotos.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            heroHeader
            if !poolIsEmpty {
                filterAndSizeRow
            }
            if showSearchField && !poolIsEmpty { searchField }
            if appState.addingToDumpId != nil && !poolIsEmpty { selectionBanner }
            if poolIsEmpty { emptyStateHero } else { grid }
        }
        .background(Theme.bg(appState.colorMode, cs).ignoresSafeArea())
        .onChange(of: pickerItems) { _, newItems in
            Task { await importPickedPhotos(newItems) }
        }
    }

    // MARK: - Hero header

    @State private var showPoolMenu = false
    @State private var isRescanning = false

    private var unusedCount: Int { allPhotos.count - usedPhotoIDs.count }

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("PHOTO POOL")
                .font(.system(size: 10, weight: .heavy))
                .tracking(2.5)
                .foregroundColor(appState.accentColor)
                .padding(.horizontal, 14)

            Text("Available Photos")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(Theme.text(appState.colorMode, cs))
                .tracking(-0.5)
                .padding(.horizontal, 14)

            HStack(alignment: .center) {
                Text("\(unusedCount) available · \(usedPhotoIDs.count) in dumps")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.text2(appState.colorMode, cs))
                Spacer()
                Button {
                    rescanAll()
                } label: {
                    HStack(spacing: 5) {
                        if isRescanning {
                            ProgressView().scaleEffect(0.6).tint(appState.accentColor)
                        }
                        Text(isRescanning ? "Scanning…" : "Rescan All")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(isRescanning ? Theme.text2(appState.colorMode, cs) : Theme.text(appState.colorMode, cs))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Theme.bg2(appState.colorMode, cs))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }
                .disabled(isRescanning)
            }
            .padding(.horizontal, 14)
            .padding(.top, 2)
        }
        .padding(.top, 4)
        .confirmationDialog("Photo Pool", isPresented: $showPoolMenu) {
            Button("Sort by Newest") { }
            Button("Show Used Photos") { appState.activeFilters = [.used] }
            Button("Show All") { appState.activeFilters.removeAll() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Combined filter + size row

    private var filterAndSizeRow: some View {
        HStack(spacing: 8) {
            Button { showPoolMenu = true } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.text(appState.colorMode, cs))
                    .frame(width: 36, height: 32)
                    .background(Theme.bg2(appState.colorMode, cs))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }

            pillButton(label: "All", icon: nil, isSelected: appState.activeFilters.isEmpty) {
                appState.activeFilters.removeAll()
            }

            pillButton(label: "Used", icon: nil, isSelected: appState.activeFilters.contains(.used)) {
                toggleFilter(.used)
            }

            Spacer()

            Button { showSearchField.toggle() } label: {
                Image(systemName: showSearchField ? "magnifyingglass.circle.fill" : "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(showSearchField ? appState.accentColor : Theme.text(appState.colorMode, cs))
                    .frame(width: 32, height: 32)
                    .background(Theme.bg2(appState.colorMode, cs))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }

            HStack(spacing: 4) {
                sizePill("S", size: .small)
                sizePill("M", size: .medium)
                sizePill("L", size: .large)
            }
        }
        .padding(.horizontal, 14)
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
            .background(isSelected ? appState.accentColor : Theme.bg2(appState.colorMode, cs))
            .clipShape(Capsule())
        }
    }

    private func sizePill(_ label: String, size: PoolSize) -> some View {
        let isSelected = appState.poolSize == size
        return Button { appState.poolSize = size } label: {
            Text(label)
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(isSelected ? .black : Theme.text2(appState.colorMode, cs))
                .frame(width: 28, height: 28)
                .background(isSelected ? appState.accentColor : Theme.bg2(appState.colorMode, cs))
                .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    private func toggleFilter(_ filter: FilterType) {
        if appState.activeFilters.contains(filter) {
            appState.activeFilters.remove(filter)
        } else {
            appState.activeFilters.insert(filter)
        }
    }

    private func rescanAll() {
        guard !allPhotos.isEmpty else { return }
        isRescanning = true
        Task { @MainActor in
            for photo in allPhotos {
                photo.category = FormulaEngine.guessCategory(filename: photo.filename)
            }
            try? modelContext.save()
            isRescanning = false
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
                        .font(.system(size: 14))
                        .foregroundColor(Theme.text3(appState.colorMode, cs))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.bg2(appState.colorMode, cs))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 14)
    }

    // MARK: - Selection banner

    private var selectionBanner: some View {
        HStack {
            Text("\(selectedPhotoIDs.count) photos selected")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.black)
            Spacer()
            Button {
                addSelectedPhotosToDump()
            } label: {
                Text("ADD TO DUMP")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.4)
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(appState.accentColor)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(appState.accentColor.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 14)
    }

    private func addSelectedPhotosToDump() {
        guard let dumpId = appState.addingToDumpId else { return }
        if let dump = allDumps.first(where: { $0.id == dumpId }) {
            dump.photoIDs.append(contentsOf: Array(selectedPhotoIDs))
            try? modelContext.save()
            appState.addingToDumpId = nil
            selectedPhotoIDs.removeAll()
        }
    }

    // MARK: - Grid

    // MARK: - Empty state hero

    @ViewBuilder
    private var emptyStateHero: some View {
        let accent = appState.accentColor
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.10))
                    .frame(width: 88, height: 88)
                Image(systemName: "photo.stack")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(accent)
            }

            VStack(spacing: 6) {
                Text("Your pool is empty")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(Theme.text(appState.colorMode, cs))
                Text("Import photos from your library to start\nbuilding dumps and generating captions.")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.text2(appState.colorMode, cs))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: 50,
                selectionBehavior: .ordered,
                matching: .images
            ) {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("IMPORT PHOTOS")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.4)
                }
                .foregroundColor(.black)
                .padding(.horizontal, 22)
                .padding(.vertical, 13)
                .background(accent)
                .clipShape(Capsule())
                .shadow(color: accent.opacity(0.30), radius: 10, x: 0, y: 4)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
        .padding(.horizontal, 28)
    }

    private var grid: some View {
        let columns = ResponsiveGrid.columns(for: appState.poolSize, screenWidth: UIScreen.main.bounds.width)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(filteredPhotos) { photo in
                PhotoCardView(
                    photo: photo,
                    context: .pool,
                    isSelected: selectedPhotoIDs.contains(photo.id),
                    slotIndex: 0,
                    totalInDump: 0,
                    size: ResponsiveGrid.photoSize(for: appState.poolSize, screenWidth: UIScreen.main.bounds.width),
                    onRemoveFromDump: nil,
                    onDelete: {
                        modelContext.delete(photo)
                        try? modelContext.save()
                    },
                    onTap: {
                        // Selection mode: toggle; otherwise PhotoCardView opens lightbox itself
                        if appState.addingToDumpId != nil {
                            if selectedPhotoIDs.contains(photo.id) {
                                selectedPhotoIDs.remove(photo.id)
                            } else {
                                selectedPhotoIDs.insert(photo.id)
                            }
                        }
                    }
                )
                .overlay(
                    Group {
                        if appState.addingToDumpId != nil && selectedPhotoIDs.contains(photo.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.green)
                        } else if usedPhotoIDs.contains(photo.id) && appState.addingToDumpId == nil && !appState.activeFilters.contains(.used) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.gray)
                        }
                    }
                )
            }
            let cellSize = ResponsiveGrid.photoSize(for: appState.poolSize, screenWidth: UIScreen.main.bounds.width)
            let cellBg = Theme.bg2(appState.colorMode, cs)
            let accent = appState.accentColor
            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: 50,
                selectionBehavior: .ordered,
                matching: .images
            ) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(accent)
                    .frame(width: cellSize.width, height: cellSize.height)
                    .background(cellBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 14)
    }

    private func importPickedPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                let filename = UUID().uuidString + ".jpg"
                let localPath = PhotoStorageManager.shared.saveImage(uiImage, filename: filename)
                let photo = DumpPhoto(
                    localPath: localPath,
                    filename: filename
                )
                modelContext.insert(photo)
            }
        }
        try? modelContext.save()
        pickerItems.removeAll()
    }
}

