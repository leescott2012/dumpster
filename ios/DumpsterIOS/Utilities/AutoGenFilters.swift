import Foundation

/// Advanced filter state for the Auto-Gen picker — native port of web's
/// `AutoGenFilters` / `applyAutoGenFilters()` (dumpster-web
/// client/src/components/AutoGenAdvanced.tsx). Mirrors the web shape 1:1:
///   - date range (dateFrom/dateTo)
///   - time-of-day window (timeFrom/timeTo) — hard: no-EXIF photos excluded
///   - categories — OR logic, any match passes
///   - mix.surprise — bypass all filters, just grab from the whole pool
///   - mix.shuffle — randomize final order
///   - vibeNote — freeform text. NOT consumed by `apply()`, same as web:
///     `applyAutoGenFilters()` never reads vibeNote either — it's forwarded
///     separately to the AI call by the caller. Native's Auto-Gen pipeline
///     (PhotoAnalyzer + FormulaEngine) is on-device/deterministic with no
///     LLM call in the loop, so there is currently nothing for it to steer.
///     Captured here for UI parity and so a future AI-driven step can read it.
struct AutoGenFilters: Equatable {
    var dateFrom: Date?
    var dateTo: Date?
    /// Only hour/minute components are read.
    var timeFrom: Date?
    var timeTo: Date?
    var categories: Set<String> = []
    var mixOn: Bool = false
    var surprise: Bool = false
    var shuffle: Bool = false
    var vibeNote: String = ""

    static let empty = AutoGenFilters()

    var isEmpty: Bool {
        dateFrom == nil && dateTo == nil && timeFrom == nil && timeTo == nil
            && categories.isEmpty && !mixOn
            && vibeNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum AutoGenFilterEngine {

    /// Applies user-controlled filters to a photo pool.
    ///
    /// HARD RULE (photos already used in a dump are always excluded) is not
    /// this function's job on native — `AISuggestView.availablePhotos`
    /// already strips used photos before this ever runs, so every candidate
    /// passed in here is guaranteed unused. This matches web's outcome
    /// (usedIds are stripped before any other filter, even Surprise mode)
    /// without needing a redundant `usedIds` parameter.
    static func apply(_ photos: [DumpPhoto], filters: AutoGenFilters) -> [DumpPhoto] {
        // Surprise bypasses every user-controlled filter below.
        if filters.mixOn && filters.surprise {
            var pool = photos
            if filters.shuffle { pool.shuffle() }
            return pool
        }

        let cal = Calendar.current
        let dateFromStart = filters.dateFrom.map { cal.startOfDay(for: $0) }
        let dateToEnd = filters.dateTo.flatMap {
            cal.date(bySettingHour: 23, minute: 59, second: 59, of: $0)
        }
        let hasDateFilter = dateFromStart != nil || dateToEnd != nil

        let timeFromMin = filters.timeFrom.map { minuteOfDay($0, cal) }
        let timeToMin = filters.timeTo.map { minuteOfDay($0, cal) }
        let hasTimeFilter = timeFromMin != nil || timeToMin != nil

        let cats = Set(filters.categories.map { $0.lowercased() })
        let hasCatFilter = !cats.isEmpty

        var out = photos.filter { photo in
            // Date range — no-metadata photos excluded whenever this filter is active.
            if hasDateFilter {
                guard let taken = photo.takenAt else { return false }
                if let from = dateFromStart, taken < from { return false }
                if let to = dateToEnd, taken > to { return false }
            }
            // Time-of-day (hard window) — no-metadata photos excluded whenever active.
            if hasTimeFilter {
                guard let taken = photo.takenAt else { return false }
                let minOfDay = minuteOfDay(taken, cal)
                if let from = timeFromMin, let to = timeToMin, from > to {
                    // Wrap-around window, e.g. 22:00 → 02:00.
                    if minOfDay < from && minOfDay > to { return false }
                } else {
                    if let from = timeFromMin, minOfDay < from { return false }
                    if let to = timeToMin, minOfDay > to { return false }
                }
            }
            // Category — OR across selected chips.
            if hasCatFilter && !cats.contains(photo.category.lowercased()) { return false }
            return true
        }

        if filters.mixOn && filters.shuffle { out.shuffle() }
        return out
    }

    private static func minuteOfDay(_ date: Date, _ cal: Calendar) -> Int {
        let c = cal.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
