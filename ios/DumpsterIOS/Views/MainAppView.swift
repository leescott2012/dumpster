import SwiftUI
import SwiftData

/// New native top-level view. Replaces `DumpsterWebView` in Phase 6.
///
/// Layout (vertical scroll):
///   ┌────────────────────────────────────────┐
///   │  HEADER: undo/redo · DUMPSTER · settings│
///   │  DUMPS LIST  (LazyVStack of DumpCardView)│
///   │  + NEW DUMP button                     │
///   │  POOL TAB SWITCHER  [ Photos | Captions ]│
///   │  PhotoPoolView  /  CaptionPoolView      │
///   └────────────────────────────────────────┘
struct MainAppView: View {

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var undoManager: DumpsterUndoManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var cs

    @Query(sort: \PhotoDump.num, order: .reverse) private var dumps: [PhotoDump]
    @Query private var allPhotos: [DumpPhoto]
    @Query(sort: \AITasteExample.createdAt, order: .reverse) private var tasteExamples: [AITasteExample]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Reserve space for the Dynamic Island pill at the top
                    Color.clear.frame(height: 50)

                    hero
                    statsBar
                    if undoManager.canUndo || undoManager.canRedo {
                        undoBar
                    }
                    dumpsSection
                    newDumpButton
                    poolTabSwitcher
                        .id("poolTop")
                    poolContent
                    Color.clear.frame(height: 80)
                }
            }
            .background(Theme.bg(appState.colorMode, cs).ignoresSafeArea())
            .preferredColorScheme(appState.colorMode == .day ? .light :
                                  appState.colorMode == .dark ? .dark : nil)
            .onAppear {
                appState.dumpCount = dumps.count
                #if DEBUG
                DebugSeeder.seedIfEmpty(context: modelContext)
                #endif
            }
            .onChange(of: dumps.count) { _, new in appState.dumpCount = new }
            .onChange(of: appState.scrollToPool) { _, trigger in
                guard trigger != nil else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    proxy.scrollTo("poolTop", anchor: .top)
                }
                appState.scrollToPool = nil
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Spacer()
            iconButton("gearshape") {
                appState.showSettings = true
            }
        }
        .padding(.horizontal, 14)
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.text(appState.colorMode, cs))
                .frame(width: 32, height: 32)
                .background(Theme.bg2(appState.colorMode, cs))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 0) {
                HStack(spacing: 0) {
                    Text("Build Your ")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(Theme.text(appState.colorMode, cs))
                    Text("Dumps")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(appState.accentColor)
                }
                .tracking(-0.6)
                Spacer(minLength: 8)
                iconButton("line.3.horizontal") {
                    appState.showFileCabinet = true
                }
                .padding(.top, 6)
            }
            Text("Rearrange photos, build new dumps, and experiment with different flows. Tap a photo to select it. Tap + to add from the pool.")
                .font(.system(size: 14))
                .foregroundColor(Theme.text2(appState.colorMode, cs))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    // MARK: - Stats bar

    private var photosUsedCount: Int {
        Set(dumps.flatMap { $0.photoIDs }).count
    }

    private var poolCount: Int {
        max(0, allPhotos.count - photosUsedCount)
    }

    private var statsBar: some View {
        HStack(spacing: 12) {
            statChip(value: dumps.count, label: dumps.count == 1 ? "Dump" : "Dumps")
            statDot
            statChip(value: photosUsedCount, label: "Photos Used")
            statDot
            statChip(value: poolCount, label: "In Pool")
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }

    private var statDot: some View {
        Circle()
            .fill(Theme.text3(appState.colorMode, cs))
            .frame(width: 3, height: 3)
    }

    private func statChip(value: Int, label: String) -> some View {
        HStack(spacing: 5) {
            Text("\(value)")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(appState.accentColor)
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(Theme.text2(appState.colorMode, cs))
        }
    }

    // MARK: - Undo / Redo

    private var undoBar: some View {
        HStack(spacing: 8) {
            undoRedoButton(symbol: "arrow.uturn.backward",
                           enabled: undoManager.canUndo,
                           action: performUndo)
            undoRedoButton(symbol: "arrow.uturn.forward",
                           enabled: undoManager.canRedo,
                           action: performRedo)
            Spacer()
        }
        .padding(.horizontal, 14)
    }

    private func undoRedoButton(symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.text(appState.colorMode, cs))
                .frame(width: 32, height: 32)
                .background(Theme.bg2(appState.colorMode, cs))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .opacity(enabled ? 1.0 : 0.4)
        }
        .disabled(!enabled)
    }

    private func performUndo() {
        guard let snap = undoManager.popUndo() else { return }
        // Capture current state into redo before restoring.
        let current = makeSnapshot()
        undoManager.pushRedo(current)
        restore(snap)
    }

    private func performRedo() {
        guard let snap = undoManager.popRedo() else { return }
        let current = makeSnapshot()
        undoManager.pushSnapshotRaw(current)
        restore(snap)
    }

    private func makeSnapshot() -> DumpsterUndoManager.Snapshot {
        DumpsterUndoManager.Snapshot(
            photoIDs: allPhotos.map { $0.id },
            dumps: dumps.map {
                DumpsterUndoManager.DumpSnapshot(
                    id: $0.id, num: $0.num, title: $0.title, photoIDs: $0.photoIDs
                )
            },
            timestamp: Date()
        )
    }

    /// Apply a snapshot of dump titles + photoIDs onto the live store.
    /// (Photo deletions/inserts within snapshots will be added in a later phase.)
    private func restore(_ snap: DumpsterUndoManager.Snapshot) {
        let liveByID = Dictionary(uniqueKeysWithValues: dumps.map { ($0.id, $0) })
        var keepIDs = Set<String>()
        for ds in snap.dumps {
            keepIDs.insert(ds.id)
            if let live = liveByID[ds.id] {
                live.num = ds.num
                live.title = ds.title
                live.photoIDs = ds.photoIDs
            } else {
                let restored = PhotoDump(
                    id: ds.id, num: ds.num, title: ds.title, photoIDs: ds.photoIDs
                )
                modelContext.insert(restored)
            }
        }
        for live in dumps where !keepIDs.contains(live.id) {
            modelContext.delete(live)
        }
        try? modelContext.save()
    }

    // MARK: - Dumps list

    private var dumpsSection: some View {
        LazyVStack(spacing: 14) {
            ForEach(dumps) { dump in
                DumpCardView(dump: dump, isActive: dump.id == appState.activeDumpId, allPhotos: allPhotos, tasteExamples: tasteExamples)
                    .onTapGesture { appState.activeDumpId = dump.id }
                    .id(dump.id) // FIX: Stabilize view identity for LazyVStack reuse
            }
        }
    }

    private var newDumpButton: some View {
        // Equal-width pills, centered — no outer Spacers (they steal space)
        HStack(spacing: 12) {
            Button {
                appState.showAISuggest = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                    Text("AUTO-GENERATE")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.4)
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(appState.accentColor)
                .clipShape(Capsule())
                .shadow(color: appState.accentColor.opacity(0.3), radius: 8, x: 0, y: 3)
            }

            Button(action: createNewDump) {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("NEW DUMP")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.4)
                }
                .foregroundColor(appState.accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.001)) // ensure full capsule is hit-testable
                .overlay(Capsule().strokeBorder(appState.accentColor, lineWidth: 1.2))
                .contentShape(Capsule())
            }
        }
        .padding(.horizontal, 20)
    }

    private func createNewDump() {
        undoManager.pushSnapshot(photos: allPhotos, dumps: dumps)
        let nextNum = (dumps.map { $0.num }.max() ?? 0) + 1
        let dump = PhotoDump(num: nextNum, title: "New Dump", photoIDs: [], isAIGenerated: false)
        modelContext.insert(dump)
        try? modelContext.save()
        appState.activeDumpId = dump.id
        // Enter pool selection mode and scroll down so user can pick photos
        appState.addingToDumpId = dump.id
        appState.activePoolTab = .photos
        appState.scrollToPool = UUID()
    }

    // MARK: - Pool tab switcher

    private var poolTabSwitcher: some View {
        HStack(spacing: 0) {
            segmentedTab("PHOTOS",   tab: .photos)
            segmentedTab("CAPTIONS", tab: .captions)
        }
        .padding(4)
        .background(
            Capsule().fill(Theme.bg2(appState.colorMode, cs))
        )
        .overlay(
            Capsule().stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .padding(.horizontal, 14)
    }

    private func segmentedTab(_ label: String, tab: PoolTab) -> some View {
        let isSel = appState.activePoolTab == tab
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                appState.activePoolTab = tab
            }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .heavy))
                .tracking(1.8)
                .foregroundColor(isSel ? appState.accentColor : Theme.text3(appState.colorMode, cs))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(isSel ? appState.accentColor.opacity(0.18) : Color.clear)
                        .overlay(
                            Capsule().stroke(isSel ? appState.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
                        )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pool content

    @ViewBuilder
    private var poolContent: some View {
        switch appState.activePoolTab {
        case .photos:   PhotoPoolView(allPhotos: allPhotos, allDumps: dumps)
        case .captions: CaptionPoolView()
        }
    }
}

