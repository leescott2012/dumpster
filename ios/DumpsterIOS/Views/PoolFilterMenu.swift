import SwiftUI

/// Hamburger filter menu for the photo pool.
/// Toggles entries in `appState.activeFilters`. Presented as a Menu (popover).
struct PoolFilterMenu: View {

    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var cs

    var body: some View {
        Menu {
            ForEach(FilterType.allCases) { filter in
                Button {
                    toggle(filter)
                } label: {
                    if appState.activeFilters.contains(filter) {
                        Label(label(for: filter), systemImage: "checkmark")
                    } else {
                        Text(label(for: filter))
                    }
                }
            }
            if !appState.activeFilters.isEmpty {
                Divider()
                Button(role: .destructive) {
                    appState.activeFilters.removeAll()
                } label: {
                    Label("Clear All", systemImage: "xmark.circle")
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.text(appState.colorMode, cs))
                .frame(width: 32, height: 32)
                .background(Theme.bg2(appState.colorMode, cs))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func toggle(_ filter: FilterType) {
        if filter == .all {
            appState.activeFilters.removeAll()
            return
        }
        if appState.activeFilters.contains(filter) {
            appState.activeFilters.remove(filter)
        } else {
            appState.activeFilters.insert(filter)
        }
    }

    private func label(for filter: FilterType) -> String {
        switch filter {
        case .all:     return "All"
        case .starred: return "Starred"
        case .huji:    return "Huji"
        case .used:    return "Used"
        case .videos:  return "Videos"
        }
    }
}
