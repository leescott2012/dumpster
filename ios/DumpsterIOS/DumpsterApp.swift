import SwiftUI
import SwiftData

@main
struct DumpsterApp: App {

    let container: ModelContainer

    init() {
        Secrets.configure()   // pre-populates API keys (file is gitignored)
        CrashReporter.shared.start()
        do {
            container = try ModelContainer(for:
                DumpPhoto.self, PhotoDump.self, DumpCaption.self,
                AITasteExample.self, SavedScrub.self, DumpChatMessage.self
            )
            // Wire shared context so AIProfileSync can reach SwiftData without
            // a context being passed on every call.
            ModelContextHolder.shared.context = container.mainContext
        } catch {
            CrashReporter.shared.capture(error, tags: ["action": "model_container_init"])
            fatalError("Failed to create model container: \(error)")
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
                    if url.scheme == "dumpster", url.host == "auth" {
                        Task { await AuthManager.shared.handleCallback(url: url) }
                    }
                }
                // Seed default captions on first install (deterministic IDs — no duplicates)
                .task {
                    AIProfileSync.shared.seedIfNeeded(context: container.mainContext)
                    // Dashboard DAU — fire once per launch when already signed in
                    // (fresh sign-ins fire from AuthManager.handleCallback instead).
                    if AuthManager.shared.isSignedIn { Analytics.track(.sessionStart) }
                }
        }
        .modelContainer(container)
    }
}
