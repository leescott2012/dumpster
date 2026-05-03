import Foundation

/// Snapshot-based undo/redo for the photo + dump model graph.
///
/// Usage contract:
///   1. Before any mutation, call `pushSnapshot(photos:dumps:)`.
///   2. The redo stack is cleared on every push (standard editor behavior).
///   3. To undo: pop a snapshot, capture the *current* state into a redo
///      snapshot via `pushRedo(_:)`, then restore the popped state.
///   4. Cap is 200 snapshots; oldest are dropped silently.
///
/// Note: this class is named `DumpsterUndoManager` to avoid clashing with
/// Foundation's `UndoManager`.
@MainActor
final class DumpsterUndoManager: ObservableObject {

    struct DumpSnapshot {
        let id: String
        let num: Int
        let title: String
        let photoIDs: [String]
    }

    struct Snapshot {
        /// All DumpPhoto IDs at snapshot time — lets us detect deletions
        /// when restoring (a photo that's gone from the live store but
        /// referenced here means it was deleted and should be undelete-able
        /// once we have full DumpPhoto field snapshots in a future phase).
        let photoIDs: [String]
        let dumps: [DumpSnapshot]
        let timestamp: Date
    }

    @Published private(set) var canUndo: Bool = false
    @Published private(set) var canRedo: Bool = false

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private let maxSnapshots = 200

    // MARK: - Push (call BEFORE mutating)

    func pushSnapshot(photos: [DumpPhoto], dumps: [PhotoDump]) {
        let snap = Snapshot(
            photoIDs: photos.map { $0.id },
            dumps: dumps.map { DumpSnapshot(id: $0.id, num: $0.num, title: $0.title, photoIDs: $0.photoIDs) },
            timestamp: Date()
        )
        undoStack.append(snap)
        redoStack.removeAll()
        if undoStack.count > maxSnapshots {
            undoStack.removeFirst(undoStack.count - maxSnapshots)
        }
        refreshFlags()
    }

    // MARK: - Pop

    /// Pop the most recent undo snapshot. Caller is responsible for capturing
    /// the *current* state into a redo snapshot via `pushRedo(_:)` before
    /// restoring the returned snapshot.
    func popUndo() -> Snapshot? {
        let s = undoStack.popLast()
        refreshFlags()
        return s
    }

    func pushRedo(_ snapshot: Snapshot) {
        redoStack.append(snapshot)
        if redoStack.count > maxSnapshots {
            redoStack.removeFirst(redoStack.count - maxSnapshots)
        }
        refreshFlags()
    }

    /// Pop the most recent redo snapshot. Caller is responsible for pushing
    /// the *current* state back onto the undo stack via `pushSnapshotRaw(_:)`
    /// or `pushSnapshot(photos:dumps:)` before restoring.
    func popRedo() -> Snapshot? {
        let s = redoStack.popLast()
        refreshFlags()
        return s
    }

    /// Push an already-built snapshot directly (no redo clear). Used when an
    /// undo restore needs to record the *previous* live state on the undo
    /// stack so a redo->undo round-trip works cleanly.
    func pushSnapshotRaw(_ snapshot: Snapshot) {
        undoStack.append(snapshot)
        if undoStack.count > maxSnapshots {
            undoStack.removeFirst(undoStack.count - maxSnapshots)
        }
        refreshFlags()
    }

    // MARK: - Maintenance

    /// Clear history older than 24 hours. Cheap to call on app foreground.
    func pruneOldSnapshots() {
        let cutoff = Date().addingTimeInterval(-86400)
        undoStack.removeAll { $0.timestamp < cutoff }
        redoStack.removeAll { $0.timestamp < cutoff }
        refreshFlags()
    }

    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
        refreshFlags()
    }

    // MARK: - Internal

    private func refreshFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }
}
