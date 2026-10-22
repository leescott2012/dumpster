import SwiftUI
import SwiftData

@main
struct DumpsterApp: App {

    let container: ModelContainer
    private let didRecoverStore: Bool
    @State private var showRecoveryAlert = false
    @ObservedObject private var credits = CreditManager.shared

    init() {
        CrashReporter.shared.start()
        let types: [any PersistentModel.Type] = [
            DumpPhoto.self, PhotoDump.self, DumpCaption.self,
            AITasteExample.self, SavedScrub.self, DumpChatMessage.self, VideoItem.self
        ]
        let schema = Schema(types)
        var recovered = false
        var made: ModelContainer?
        do {
            made = try ModelContainer(for: schema)
        } catch {
            CrashReporter.shared.capture(error, tags: ["action": "model_container_init"])
            // Recovery: move the unreadable store aside (kept as .bak, not deleted) and start fresh.
            // Last resort: in-memory so the app still launches instead of crashing.
            Self.moveStoreAside()
            recovered = true
            made = try? ModelContainer(for: schema)
            if made == nil {
                made = try? ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            }
        }
        guard let ready = made else {
            // In-memory creation only fails if the schema itself is invalid (a build-time bug).
            preconditionFailure("SwiftData schema is invalid")
        }
        container = ready
        didRecoverStore = recovered
        // Wire shared context so AIProfileSync can reach SwiftData without
        // a context being passed on every call.
        ModelContextHolder.shared.context = ready.mainContext
    }

    /// Renames default.store (+ -wal/-shm) to *.bak-<timestamp>. Non-destructive.
    private static func moveStoreAside() {
        let fm = FileManager.default
        guard let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        for suffix in ["", "-wal", "-shm"] {
            let src = dir.appendingPathComponent("default.store" + suffix)
            if fm.fileExists(atPath: src.path) {
                try? fm.moveItem(at: src, to: dir.appendingPathComponent("default.store\(suffix).bak-\(stamp)"))
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .ignoresSafeArea()
                .environmentObject(AuthManager.shared)
                // Handle Supabase magic link deep link:
                // dumpster://auth/callback?token_hash=...&type=magiclink
                .onOpenURL { url in
                    ReferralManager.shared.capture(url: url)
                    if url.scheme == "dumpster", url.host == "auth" {
                        Task { await AuthManager.shared.handleCallback(url: url) }
                    }
                }
                // Seed default captions on first install (deterministic IDs — no duplicates)
                .sheet(isPresented: $credits.showOutOfCredits) { PaywallView().presentationDetents([.large]) }
                .alert("Local data was reset", isPresented: $showRecoveryAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("Your on-device library couldn't be opened after an update. If you're signed in, your synced data will come back from your account.")
                }
                .task {
                    showRecoveryAlert = didRecoverStore
                    AIProfileSync.shared.seedIfNeeded(context: container.mainContext)
                    // Dashboard DAU — fire once per launch when already signed in
                    // (fresh sign-ins fire from AuthManager.handleCallback instead).
                    if AuthManager.shared.isSignedIn { Analytics.track(.sessionStart) }
                }
        }
        .modelContainer(container)
    }
}
