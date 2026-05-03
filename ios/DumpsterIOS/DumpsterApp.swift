import SwiftUI
import SwiftData

@main
struct DumpsterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .ignoresSafeArea()
        }
        .modelContainer(for: [DumpPhoto.self, PhotoDump.self, DumpCaption.self])
    }
}
