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

    @Query(sort: \PhotoDump.createdAt, order: .forward) private var dumps: [PhotoDump]
    @Query private var allPhotos: [DumpPhoto]
    @Query(sort: \AITasteExample.createdAt, order: .reverse) private var tasteExamples: [AITasteExample]

    @State private var poolTabSegmentWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pillDragOffset: CGFloat = 0
    @State private var isDraggingPill: Bool = false
    @State private var showArchived: Bool = false

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
                    Color.clear.frame(height: 12)
                    newDumpButton
                    sectionDivider
                        .padding(.top, 18)
                        .padding(.bottom, 4)
                    poolTabSwitcher
                        .id("poolTop")
                    poolContent
                    Color.clear.frame(height: 80)
                }
            }
            .background(Theme.bg(appState.colorMode, cs).ignoresSafeArea())
            // The always-black "Dynamic Island" pill in ContentView (Contentview.swift)
            // sits directly behind the status bar and never changes with the theme, so a
            // light-theme (dark-content) status bar goes invisible against it. Only follow
            // the theme when the File Cabinet menu is up — its own opaque background fully
            // covers that pill, so dark-content icons contrast correctly there. Otherwise
            // force dark scheme (light-content icons) so the status bar stays readable.
            .preferredColorScheme(appState.showFileCabinet
                ? (appState.colorMode == .day ? .light : appState.colorMode == .dark ? .dark : nil)
                : .dark)
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
        let active = dumps.filter { !$0.archived }
        let archived = dumps.filter { $0.archived }
        return LazyVStack(spacing: 14) {
            ForEach(active) { dump in
                DumpCardView(dump: dump, isActive: dump.id == appState.activeDumpId, allPhotos: allPhotos, tasteExamples: tasteExamples)
                    .onTapGesture { appState.activeDumpId = dump.id }
                    .id(dump.id) // FIX: Stabilize view identity for LazyVStack reuse
            }

            // Archived dumps — collapsed by default so saved dumps stay out of
            // the way (parity with web Home.tsx archived section).
            if !archived.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showArchived.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showArchived ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                        Text("ARCHIVED (\(archived.count))")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(1.4)
                        Spacer()
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 6)
                }
                if showArchived {
                    ForEach(archived) { dump in
                        DumpCardView(dump: dump, isActive: dump.id == appState.activeDumpId, allPhotos: allPhotos, tasteExamples: tasteExamples)
                            .onTapGesture { appState.activeDumpId = dump.id }
                            .id(dump.id)
                            .opacity(0.75)
                    }
                }
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

    // MARK: - Section divider (between New Dump area and Pool)

    private var sectionDivider: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Theme.text3(appState.colorMode, cs).opacity(0.25))
                .frame(height: 1)
            Text("POOL")
                .font(.system(size: 10, weight: .heavy))
                .tracking(2.5)
                .foregroundColor(Theme.text3(appState.colorMode, cs))
            Rectangle()
                .fill(Theme.text3(appState.colorMode, cs).opacity(0.25))
                .frame(height: 1)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Pool tab switcher

    private var poolTabSwitcher: some View {
        let tabs: [(String, String, PoolTab)] = [
            ("Photos", "photo", .photos), ("Captions", "textformat", .captions), ("Videos", "play.rectangle", .videos)
        ]
        let selectedIndex = tabs.firstIndex { $0.2 == appState.activePoolTab } ?? 0
        let snap: Animation? = reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7)

        return GeometryReader { geo in
            let inset: CGFloat = 4
            let segWidth = (geo.size.width - inset * 2) / CGFloat(tabs.count)
            let baseOffset = inset + CGFloat(selectedIndex) * segWidth
            let maxOffset = inset + CGFloat(tabs.count - 1) * segWidth
            let liveOffset = min(maxOffset, max(inset, baseOffset + pillDragOffset))

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.bg2(appState.colorMode, cs))

                // Gold-outlined thumb: follows finger 1:1 while dragging, springs on release
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(Theme.gold, lineWidth: 1.5))
                    .frame(width: max(0, segWidth), height: geo.size.height - inset * 2)
                    .offset(x: liveOffset)
                    .animation(isDraggingPill ? nil : snap, value: liveOffset)

                HStack(spacing: 0) {
                    ForEach(Array(tabs.enumerated()), id: \.offset) { _, item in
                        let isSel = appState.activePoolTab == item.2
                        VStack(spacing: 2) {
                            Image(systemName: item.1).font(.system(size: 17, weight: .semibold))
                            Text(item.0).font(.system(size: 9, weight: .bold))
                        }
                        .foregroundColor(isSel ? Theme.gold : Theme.text3(appState.colorMode, cs))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(item.0)
                        .accessibilityAddTraits(isSel ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { switchPoolTab(to: item.2) }
                    }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
            .contentShape(Rectangle())
            // minimumDistance 0 handles taps too (a tap = zero-travel drag snaps to the tapped segment).
            // Horizontal-only pill, so vertical scrolling elsewhere is unaffected.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Thumb centre tracks the finger; a tap jumps the thumb under the finger.
                        isDraggingPill = true
                        pillDragOffset = value.location.x - segWidth / 2 - baseOffset
                    }
                    .onEnded { value in
                        let idx = max(0, min(tabs.count - 1, Int((value.location.x - inset) / segWidth)))
                        let target = tabs[idx].2
                        withAnimation(snap) {
                            pillDragOffset = 0
                            isDraggingPill = false
                            if appState.activePoolTab != target {
                                HapticManager.shared.playTick()
                                appState.activePoolTab = target
                            }
                        }
                    }
            )
        }
        .frame(height: 52)
        .padding(.horizontal, 14)
    }

    private func switchPoolTab(to tab: PoolTab) {
        guard appState.activePoolTab != tab else { return }
        HapticManager.shared.playTick()
        // Set state directly — the highlight animates via its own .animation(value:) modifier.
        // Wrap content transition in withTransaction for the slide-in effect.
        withTransaction(Transaction(animation: .spring(response: 0.45, dampingFraction: 0.85))) {
            appState.activePoolTab = tab
        }
    }

    // MARK: - Pool content

    @ViewBuilder
    private var poolContent: some View {
        Group {
            switch appState.activePoolTab {
            case .photos:
                PhotoPoolView(allPhotos: allPhotos, allDumps: dumps)
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            case .captions:
                CaptionPoolView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            case .videos:
                // ponytail: native has no Video Pool model yet (no duration/asset list). Videos are device-only, never cloud.
                VStack(spacing: 10) {
                    Image(systemName: "play.rectangle").font(.system(size: 36))
                    Text("Videos stay on this device").font(.system(size: 15, weight: .semibold))
                    Text("Your videos are never uploaded.").font(.system(size: 12))
                }
                .foregroundColor(Theme.text3(appState.colorMode, cs))
                .frame(maxWidth: .infinity).padding(.vertical, 60)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    let h = value.translation.width
                    let v = value.translation.height
                    // Only trigger when motion is mostly horizontal
                    guard abs(h) > abs(v) * 1.5, abs(h) > 50 else { return }
                    let order: [PoolTab] = [.photos, .captions, .videos]
                    guard let i = order.firstIndex(of: appState.activePoolTab) else { return }
                    let j = h < 0 ? i + 1 : i - 1
                    if order.indices.contains(j) { switchPoolTab(to: order[j]) }
                }
        )
    }
}

