import Foundation

// MARK: - App-wide enums
//
// The conversion spec puts these as nested types on AppState, but they are
// referenced by Theme + many views and must exist before AppState is rewritten.
// Phase 2 (AppState rewrite) will reference these directly — no nesting needed.

enum ColorMode: String, CaseIterable {
    case dark, day, system
}

enum PoolSize: String, CaseIterable {
    case small, medium, large

    var columnCount: Int {
        switch self {
        case .small:  return 6
        case .medium: return 4
        case .large:  return 2
        }
    }
}

enum FilterType: String, CaseIterable, Identifiable {
    case all, huji, used, videos
    var id: String { rawValue }
}

enum PoolTab: String {
    case photos, captions
}
