import Foundation

/// Direct port of `src/formula.ts` — the @catchcanary carousel arrangement engine.
/// Pure functions; no UI or persistence side effects.
///
/// Templates:
///   • photos.count >= 10 → 12-slot template
///   • photos.count <  10 → 7-slot tight edit
/// In both, position 0 is THE HOOK and the last position is THE CLOSER.
/// Middle slots are shuffled for variety on each call.
enum FormulaEngine {

    // MARK: - Category Display Names

    static let categoryDisplay: [String: String] = [
        "PORTRAIT":     "Face",
        "AUTOMOTIVE":   "Car",
        "NIGHTLIFE":    "Night",
        "ART":          "Museum",
        "FITNESS":      "Gym",
        "ABSTRACT":     "Abstract",
        "FASHION":      "Style",
        "ARCHITECTURE": "Space",
        "TRAVEL":       "Travel",
        "DINING":       "Eats",
        "WATCH":        "Watch",
        "LIFESTYLE":    "Life",
        "SCENE":        "Scene",
        "STUDIO":       "Studio"
    ]

    // MARK: - Slot Roles

    enum SlotRole: String, CaseIterable {
        case hook
        case contrast
        case detail
        case fashion
        case culture
        case watch
        case secondCar      = "second-car"
        case insider
        case atmosphere
        case secondFashion  = "second-fashion"
        case wildcard
        case closer
    }

    static let slotLabels: [SlotRole: String] = [
        .hook:           "THE HOOK",
        .contrast:       "THE CONTRAST",
        .detail:         "THE DETAIL",
        .fashion:        "THE FASHION BEAT",
        .culture:        "THE CULTURAL MOMENT",
        .watch:          "THE WATCH",
        .secondCar:      "THE SECOND CAR",
        .insider:        "THE INSIDER",
        .atmosphere:     "THE ATMOSPHERE",
        .secondFashion:  "SECOND FASHION BEAT",
        .wildcard:       "THE WILDCARD",
        .closer:         "THE CLOSER"
    ]

    static let template12: [SlotRole] = [
        .hook, .contrast, .detail, .fashion, .culture, .watch,
        .secondCar, .insider, .atmosphere, .secondFashion, .wildcard, .closer
    ]

    static let template7: [SlotRole] = [
        .hook, .contrast, .detail, .fashion, .culture, .secondCar, .closer
    ]

    // MARK: - Slot Scores

    /// 0–10 score per slot × category. Lookups default to 2 (see `scoreForSlot`).
    static let slotScores: [SlotRole: [String: Int]] = [
        .hook:           ["PORTRAIT": 10, "AUTOMOTIVE": 10, "ART": 7, "FASHION": 5, "NIGHTLIFE": 5],
        .contrast:       ["AUTOMOTIVE": 10, "PORTRAIT": 8, "ARCHITECTURE": 6],
        .detail:         ["WATCH": 10, "FASHION": 8, "AUTOMOTIVE": 6, "PORTRAIT": 5],
        .fashion:        ["FASHION": 10, "PORTRAIT": 6, "LIFESTYLE": 4],
        .culture:        ["ART": 10, "PORTRAIT": 7, "LIFESTYLE": 5],
        .watch:          ["WATCH": 10, "FASHION": 5],
        .secondCar:      ["AUTOMOTIVE": 10, "ARCHITECTURE": 5],
        .insider:        ["PORTRAIT": 10, "NIGHTLIFE": 7, "LIFESTYLE": 5],
        .atmosphere:     ["ARCHITECTURE": 10, "TRAVEL": 10, "NIGHTLIFE": 8, "SCENE": 10],
        .secondFashion:  ["FASHION": 10, "PORTRAIT": 6],
        .wildcard:       ["DINING": 10, "ART": 8, "ARCHITECTURE": 7, "TRAVEL": 7, "LIFESTYLE": 6],
        .closer:         ["ARCHITECTURE": 10, "TRAVEL": 10, "NIGHTLIFE": 8, "ART": 8, "PORTRAIT": 7]
    ]

    // MARK: - Scoring

    /// Used to pick the slide-1 hook. Internal-only in the TS source.
    static func hookScore(for photo: DumpPhoto) -> Int {
        switch photo.category.uppercased() {
        case "PORTRAIT":   return 10
        case "AUTOMOTIVE": return 10
        case "ART":        return 7
        case "NIGHTLIFE":  return 6
        case "FASHION":    return 5
        default:           return 3
        }
    }

    static func scoreForSlot(_ photo: DumpPhoto, slot: SlotRole) -> Int {
        let cat = photo.category.uppercased()
        return slotScores[slot]?[cat] ?? 2
    }

    // MARK: - Arrange Photos

    /// Auto-arrange photos into the best template order.
    /// Hook (slot 0) and closer (last) are fixed by template; middle slots are
    /// shuffled per call so re-runs feel fresh. Each photo is then placed in the
    /// remaining slot it scores highest for.
    static func arrangePhotos(_ photos: [DumpPhoto]) -> [DumpPhoto] {
        guard !photos.isEmpty else { return [] }
        let template = photos.count >= 10 ? template12 : template7
        let slots = Array(template.prefix(photos.count))

        guard slots.count > 1 else { return [photos[0]] }

        let hook = slots[0]
        let closer = slots[slots.count - 1]
        let middle = Array(slots[1..<(slots.count - 1)]).shuffled()
        let varied: [SlotRole] = [hook] + middle + [closer]

        var remaining = photos
        var result: [DumpPhoto?] = Array(repeating: nil, count: varied.count)

        for (slotIdx, slot) in varied.enumerated() {
            guard !remaining.isEmpty else { break }
            var bestIdx = 0
            var bestScore = -1
            for (i, photo) in remaining.enumerated() {
                let s = scoreForSlot(photo, slot: slot)
                if s > bestScore {
                    bestScore = s
                    bestIdx = i
                }
            }
            result[slotIdx] = remaining[bestIdx]
            remaining.remove(at: bestIdx)
        }

        return result.compactMap { $0 }
    }

    // MARK: - Slot Lookup

    static func getSlotRole(index: Int, total: Int) -> SlotRole? {
        let template = total >= 10 ? template12 : template7
        guard index < template.count else { return nil }
        return template[index]
    }

    // MARK: - Vibe Check

    /// Returns false (mismatch) when a dump mixes >25% warm and >25% cool photos.
    /// Trivial dumps (<3 photos) always return true.
    static func checkColorTemp(_ photos: [DumpPhoto]) -> Bool {
        guard photos.count >= 3 else { return true }
        let warm = photos.filter { ["TRAVEL", "DINING", "FITNESS"].contains($0.category.uppercased()) }.count
        let cool = photos.filter { ["NIGHTLIFE", "ARCHITECTURE", "STUDIO"].contains($0.category.uppercased()) }.count
        let warmRatio = Double(warm) / Double(photos.count)
        let coolRatio = Double(cool) / Double(photos.count)
        return !(warmRatio > 0.25 && coolRatio > 0.25)
    }

    // MARK: - Title Generation

    /// Generate a creative dump title based on the photos' categories.
    /// Multi-category combos take precedence; otherwise a primary-category pool is sampled.
    static func generateDumpTitle(for photos: [DumpPhoto]) -> String {
        guard !photos.isEmpty else { return "New Dump" }

        var counts: [String: Int] = [:]
        for p in photos { counts[p.category.uppercased(), default: 0] += 1 }
        let sorted = counts.sorted { $0.value > $1.value }
        let primary = sorted.first?.key ?? "LIFESTYLE"
        let secondary: String? = sorted.count > 1 ? sorted[1].key : nil

        func pick(_ arr: [String]) -> String { arr.randomElement() ?? "New Dump" }

        // Multi-category combos
        if primary == "NIGHTLIFE" && secondary == "AUTOMOTIVE" {
            return pick(["Night Drives", "After Midnight", "The Late Run", "City After Dark"])
        }
        if primary == "AUTOMOTIVE" && secondary == "FASHION" {
            return pick(["Dressed to Drive", "The Style Run", "The Flex", "Moving in Style"])
        }
        if primary == "PORTRAIT" && secondary == "NIGHTLIFE" {
            return pick(["Night Faces", "Who Was There", "The Room", "Present"])
        }
        if primary == "FASHION" && secondary == "ARCHITECTURE" {
            return pick(["The Location Scout", "Sharp Angles", "The Set", "Built Different"])
        }

        switch primary {
        case "NIGHTLIFE":
            return pick([
                "After Hours", "Nightfall", "Dark Hours", "2am Energy",
                "The Night", "Past Midnight", "Still Up", "Late"
            ])
        case "AUTOMOTIVE":
            return pick([
                "The Drive", "On The Road", "Moving", "The Run",
                "Behind The Wheel", "Push", "Keys Out", "In Motion"
            ])
        case "FASHION":
            return pick([
                "The Fit", "Dressed", "The Look", "Sharp",
                "On", "The Outfit", "Fitted", "Clean"
            ])
        case "ART":
            return pick([
                "Culture Drop", "The Gallery", "Studied", "Eyes Open",
                "The Museum Run", "Seen It", "The Wall"
            ])
        case "PORTRAIT":
            return pick([
                "Faces", "Present", "In Frame", "The Shot",
                "Caught Something", "Who Was There", "The People"
            ])
        case "TRAVEL":
            return pick([
                "On Location", "Away", "Out There", "The Trip",
                "Somewhere", "Different Timezone", "Moved"
            ])
        case "FITNESS":
            return pick([
                "Work Mode", "Locked In", "Session", "The Process",
                "Gains", "No Days Off", "The Work"
            ])
        case "ARCHITECTURE":
            return pick([
                "The Space", "Built", "Interiors", "The Building",
                "Good Rooms", "Structure", "The Environment"
            ])
        case "DINING":
            return pick([
                "The Table", "Last Night", "Good Evening", "What We Ate",
                "The Dinner", "Worth It", "The Reservation"
            ])
        case "WATCH":
            return pick([
                "On The Wrist", "Time", "The Piece", "Worn Well",
                "The Detail", "Worth Wearing"
            ])
        case "STUDIO":
            return pick([
                "In The Studio", "Session", "The Work", "Locked In",
                "Made Something", "The Process"
            ])
        default:
            return pick([
                "The Edit", "Recent", "What Happened", "A Few Things",
                "Filed", "Documented", "Worth Saving"
            ])
        }
    }

    // MARK: - Filename Heuristics

    /// Best-effort category guess from a filename — used as a fallback when
    /// Apple Vision hasn't classified the image yet.
    static func guessCategory(filename: String) -> String {
        let f = filename.lowercased()
        if f.contains("portrait") || f.contains("selfie") || f.contains("face") { return "PORTRAIT" }
        if f.contains("car") || f.contains("auto") || f.contains("bmw") || f.contains("porsche") || f.contains("ferrari") { return "AUTOMOTIVE" }
        if f.contains("studio") || f.contains("ssl") || f.contains("mix") { return "STUDIO" }
        if f.contains("night") || f.contains("club") || f.contains("bar") { return "NIGHTLIFE" }
        if f.contains("gym") || f.contains("fit") { return "FITNESS" }
        if f.contains("art") || f.contains("museum") || f.contains("gallery") { return "ART" }
        if f.contains("arch") || f.contains("hotel") || f.contains("build") { return "ARCHITECTURE" }
        if f.contains("travel") || f.contains("beach") || f.contains("miami") { return "TRAVEL" }
        if f.contains("fashion") || f.contains("gucci") || f.contains("balenc") { return "FASHION" }
        if f.contains("watch") || f.contains("rm") || f.contains("patek") || f.contains("rolex") { return "WATCH" }
        return "LIFESTYLE"
    }

    /// Detects Huji / film-style filenames so the UI can flag them with the red outline.
    static func detectHuji(filename: String) -> Bool {
        let f = filename.lowercased()
        return f.contains("huji") || f.contains("dexp") || f.contains("film") || f.contains("disposable")
    }
}
