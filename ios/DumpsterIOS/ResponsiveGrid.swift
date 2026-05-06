import SwiftUI

// MARK: - ResponsiveGrid
//
// Calculates grid columns and photo sizes based on the user's preferred PoolSize.
// PoolSize is defined in Models/AppEnums.swift — do NOT redefine it here.

struct ResponsiveGrid {

    /// Returns the LazyVGrid column configuration for the given pool size.
    static func columns(for size: PoolSize, screenWidth: CGFloat) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 4), count: size.columnCount)
    }

    /// Returns the square CGSize each photo card should occupy.
    static func photoSize(for size: PoolSize, screenWidth: CGFloat) -> CGSize {
        let padding: CGFloat = 28   // 14 pt on each side
        let spacing: CGFloat = 4
        let count = CGFloat(size.columnCount)
        let availableWidth = screenWidth - padding
        let itemWidth = (availableWidth - (spacing * (count - 1))) / count
        return CGSize(width: itemWidth, height: itemWidth)
    }
}
