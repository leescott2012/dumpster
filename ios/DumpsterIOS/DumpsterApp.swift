import SwiftUI
import SwiftData

@main
struct DumpsterApp: App {

    init() {
        CrashReporter.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .ignoresSafeArea()
        }
        .modelContainer(for: [DumpPhoto.self, PhotoDump.self, DumpCaption.self, AITasteExample.self])
    }
}
