import Foundation
import SwiftData

// MARK: - Label Health
//
// Native port of client/src/lib/labelHealth.ts + hooks/useLabelHealth.ts.
// Pure metrics at the top; the manager (store + background auto-fix) below.
// Device-local (UserDefaults) — not cloud-synced, same as web.
//
// HARD RULE: videos never go to the cloud/AI. Every metric and every request
// filters them out first (isVideo). Only { id, image } is ever sent — no EXIF/GPS.

enum LabelHealthConst {
    static let categories = [
        "AUTOMOTIVE", "SELFIE", "NIGHTLIFE", "DINING", "FITNESS", "TRAVEL",
        "ARCHITECTURE", "ART", "FASHION", "STUDIO", "CULTURE", "LIFESTYLE",
    ]
    static let lowConfidence = 0.6
    static let minChecksForScore = 5
    static let auditPerDay = 6
    static let batch = 6                       // photos per auto request (server cap)
    static let requestsPerRun = 3              // server burst limit: 3 req / 10 min
    static let runEvery: TimeInterval = 10 * 60
    static let relabelCooldown: TimeInterval = 7 * 86_400
}

struct LabelInfo: Codable, Equatable {
    var confidence: Double?
    var source: String            // "ai" | "user"
    var labeledAt: Double         // unix seconds
    var audit: String?            // "agree" | "disagree" | "corrected"
}

struct LabelCheck: Codable, Equatable {
    var id: String
    var kind: String              // "verified" | "corrected" | "agree" | "disagree"
    var at: Double
}

struct LabelHealthStore: Codable {
    var info: [String: LabelInfo] = [:]
    var checks: [LabelCheck] = []
    var autoFix = true            // default on
    var auditDay = ""
    var auditCount = 0
}

/// Value snapshot of a photo — keeps the pure functions free of SwiftData.
struct LabelPhoto: Identifiable, Equatable {
    let id: String
    let path: String
    let category: String
    let alt: String

    var isVideo: Bool {
        let c = category.lowercased()
        let ext = (path as NSString).pathExtension.lowercased()
        return c == "video" || ["mov", "mp4", "m4v"].contains(ext)
    }
}

enum SuspectReason: String {
    case unlabeled = "Needs a current category + specific label"
    case lowConfidence = "AI wasn't sure"
    case auditDisagree = "Second check disagreed"
    case duplicateGeneric = "Same label as many others"
}

struct LabelHealth {
    enum Status { case green, amber, red }
    var total = 0
    var labeled = 0
    var coverage = 1.0
    var unlabeled: [LabelPhoto] = []
    var suspects: [(photo: LabelPhoto, reason: SuspectReason)] = []
    var score: Int?
    var basis = 0
    var status: Status = .green
}

enum LabelMetrics {
    private static let generic: Set<String> = ["photo", "image", "picture", "scene", "view", "moment", "vibe", "aesthetic",
        "food", "car", "building", "person", "outfit", "uncategorized", "untitled", "uploaded"]

    /// True when the label carries no real information (empty, banned word, one word, or a filename).
    static func isGeneric(_ label: String) -> Bool {
        let t = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return true }
        if t.range(of: #"\.(jpe?g|png|heic|heif|webp|gif)$"#, options: .regularExpression) != nil
            || t.range(of: #"^(img|dsc|pxl|screenshot)[_\- ]?\d"#, options: .regularExpression) != nil { return true }
        if generic.contains(t) { return true }
        return t.split(whereSeparator: { $0.isWhitespace }).count < 2
    }

    static func isValidCategory(_ c: String) -> Bool { LabelHealthConst.categories.contains(c.uppercased()) }

    enum Status { case unlabeled, suspect(SuspectReason), ok }

    /// Labeled = category in the current taxonomy AND a non-generic label. Suspect =
    /// low confidence, audit disagreed, or 3+ photos sharing identical text.
    /// User-set labels are never suspect.
    static func classify(_ photos: [LabelPhoto], _ info: [String: LabelInfo]) -> [(LabelPhoto, Status)] {
        let list = photos.filter { !$0.isVideo }
        var counts: [String: Int] = [:]
        for p in list {
            let k = p.alt.trimmingCharacters(in: .whitespaces).lowercased()
            if !k.isEmpty { counts[k, default: 0] += 1 }
        }
        return list.map { p in
            let i = info[p.id]
            let userOwned = i?.source == "user"
            if !userOwned && (!isValidCategory(p.category) || isGeneric(p.alt)) { return (p, .unlabeled) }
            if userOwned { return (p, .ok) }
            if i?.audit == "disagree" { return (p, .suspect(.auditDisagree)) }
            if let c = i?.confidence, c < LabelHealthConst.lowConfidence { return (p, .suspect(.lowConfidence)) }
            if (counts[p.alt.trimmingCharacters(in: .whitespaces).lowercased()] ?? 0) >= 3 { return (p, .suspect(.duplicateGeneric)) }
            return (p, .ok)
        }
    }

    /// hits = 2×verified + 1×audit agree; misses = 2×corrected + 1×audit disagree;
    /// score = round(100·hits/(hits+misses)). Nil under 5 checks. Latest check per
    /// photo+signal only, over the last 200 checks.
    static func accuracy(_ checks: [LabelCheck]) -> (score: Int?, basis: Int) {
        var latest: [String: LabelCheck] = [:]
        for c in checks.suffix(200) {
            let group = (c.kind == "agree" || c.kind == "disagree") ? "audit" : "user"
            latest[c.id + ":" + group] = c
        }
        var hits = 0, misses = 0
        for c in latest.values {
            switch c.kind {
            case "verified": hits += 2
            case "corrected": misses += 2
            case "agree": hits += 1
            default: misses += 1
            }
        }
        let basis = latest.count
        guard basis >= LabelHealthConst.minChecksForScore, hits + misses > 0 else { return (nil, basis) }
        return (Int((100 * Double(hits) / Double(hits + misses)).rounded()), basis)
    }

    static func compute(_ photos: [LabelPhoto], _ store: LabelHealthStore) -> LabelHealth {
        let rows = classify(photos, store.info)
        var h = LabelHealth()
        for (p, s) in rows {
            switch s {
            case .unlabeled: h.unlabeled.append(p)
            case .suspect(let r): h.suspects.append((p, r))
            case .ok: break
            }
        }
        h.total = rows.count
        h.labeled = h.total - h.unlabeled.count
        h.coverage = h.total == 0 ? 1 : Double(h.labeled) / Double(h.total)
        let acc = accuracy(store.checks)
        h.score = acc.score
        h.basis = acc.basis
        let suspectShare = h.total == 0 ? 0 : Double(h.suspects.count) / Double(h.total)
        if h.coverage < 0.7 || (acc.score ?? 100) < 70 { h.status = .red }
        else if h.coverage >= 0.95 && suspectShare <= 0.05 && (acc.score ?? 100) >= 85 { h.status = .green }
        else { h.status = .amber }
        return h
    }

    /// Random sample of AI-labeled "ok" photos whose current label hasn't been audited yet.
    static func auditSample(_ photos: [LabelPhoto], _ info: [String: LabelInfo], n: Int) -> [LabelPhoto] {
        let pool = classify(photos, info).compactMap { (p, s) -> LabelPhoto? in
            if case .ok = s, !(info[p.id]?.source == "user" || info[p.id]?.audit != nil) { return p }
            return nil
        }
        return Array(pool.shuffled().prefix(n))
    }

    static func dayKey(_ d: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

// MARK: - Manager

@MainActor
final class LabelHealthManager: ObservableObject {
    static let shared = LabelHealthManager()

    enum FixStatus: Equatable {
        case idle, running
        case paused(until: Date, daily: Bool)
    }

    @Published private(set) var store: LabelHealthStore
    @Published private(set) var fix: FixStatus = .idle

    private static let key = "label_health_v1"
    private var lastRun = Date.distantPast
    private var debounce: Task<Void, Never>?

    /// Bumped on account switch so a run that started for the previous account stops touching state.
    private var generation = 0

    private init() { store = Self.loadStore() }

    private static func loadStore() -> LabelHealthStore {
        if let data = UserDefaults.standard.data(forKey: key),
           let s = try? JSONDecoder().decode(LabelHealthStore.self, from: data) { return s }
        return LabelHealthStore()
    }

    /// Account switched: UserDefaults now hold the new account's data — reload and drop any in-flight run.
    func reloadForAccountChange() {
        generation += 1
        debounce?.cancel()
        fix = .idle
        lastRun = .distantPast
        store = Self.loadStore()
    }

    // MARK: Persistence

    private func mutate(_ f: (inout LabelHealthStore) -> Void) {
        var s = store
        f(&s)
        s.checks = Array(s.checks.suffix(300))
        store = s
        if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    func setAutoFix(_ on: Bool) {
        mutate { $0.autoFix = on }
        if on { scheduleRun() }
    }

    func isUserOwned(_ id: String) -> Bool { store.info[id]?.source == "user" }

    // MARK: Photos

    static func snapshot(_ photos: [DumpPhoto]) -> [LabelPhoto] {
        photos.map { LabelPhoto(id: $0.id, path: $0.localPath, category: $0.category, alt: $0.labels.first ?? "") }
    }

    private func allPhotos() -> [DumpPhoto] {
        guard let ctx = ModelContextHolder.shared.context else { return [] }
        return (try? ctx.fetch(FetchDescriptor<DumpPhoto>())) ?? []
    }

    private func save() { try? ModelContextHolder.shared.context?.save() }

    // MARK: Applying labels

    /// Apply AI labels, never overwriting a user-set label; records provenance.
    /// Returns the ids actually applied.
    @discardableResult
    func applyAI(_ results: [LabelService.LabelResult]) -> [String] {
        let byId = Dictionary(uniqueKeysWithValues: allPhotos().map { ($0.id, $0) })
        let now = Date().timeIntervalSince1970
        var applied: [String] = []
        for r in results where !isUserOwned(r.id) {
            guard let p = byId[r.id], !LabelPhoto(id: p.id, path: p.localPath, category: p.category, alt: "").isVideo else { continue }
            p.category = r.category.uppercased()
            p.labels = [r.label]
            applied.append(r.id)
        }
        guard !applied.isEmpty else { return [] }
        save()
        let conf = Dictionary(results.map { ($0.id, $0.confidence) }, uniquingKeysWith: { a, _ in a })
        mutate { s in
            for id in applied { s.info[id] = LabelInfo(confidence: conf[id] ?? nil, source: "ai", labeledAt: now, audit: nil) }
        }
        return applied
    }

    /// Paid Scan wrote these labels itself — just record provenance + confidence.
    func noteScan(_ results: [LabelService.LabelResult]) {
        let now = Date().timeIntervalSince1970
        mutate { s in
            for r in results where s.info[r.id]?.source != "user" {
                s.info[r.id] = LabelInfo(confidence: r.confidence, source: "ai", labeledAt: now, audit: nil)
            }
        }
    }

    private func recordAudit(_ results: [LabelService.LabelResult], photos: [String: LabelPhoto]) {
        let now = Date().timeIntervalSince1970
        mutate { s in
            for r in results {
                guard let p = photos[r.id], s.info[p.id]?.source != "user" else { continue }
                let kind = r.category.uppercased() == p.category.uppercased() ? "agree" : "disagree"
                var i = s.info[p.id] ?? LabelInfo(confidence: nil, source: "ai", labeledAt: now, audit: nil)
                i.audit = kind
                s.info[p.id] = i
                s.checks.append(LabelCheck(id: p.id, kind: kind, at: now))
            }
            let today = LabelMetrics.dayKey()
            s.auditCount = (s.auditDay == today ? s.auditCount : 0) + results.count
            s.auditDay = today
        }
    }

    // MARK: User actions

    /// "Looks right" — primary accuracy hit; locks the label to the user.
    func verify(_ photoId: String) {
        guard !isUserOwned(photoId) else { return }
        let now = Date().timeIntervalSince1970
        mutate { s in
            var i = s.info[photoId] ?? LabelInfo(confidence: nil, source: "ai", labeledAt: now, audit: nil)
            i.source = "user"
            s.info[photoId] = i
            s.checks.append(LabelCheck(id: photoId, kind: "verified", at: now))
        }
    }

    /// User edit — a miss if it changed an AI label. Locks the label to the user.
    func edit(_ photo: LabelPhoto, category: String, label: String) {
        let clean = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let p = allPhotos().first(where: { $0.id == photo.id }) else { return }
        let wasAI = !isUserOwned(photo.id) && LabelMetrics.isValidCategory(photo.category) && !LabelMetrics.isGeneric(photo.alt)
        let changed = category.uppercased() != photo.category.uppercased() || clean != photo.alt.trimmingCharacters(in: .whitespacesAndNewlines)
        p.category = category.uppercased()
        p.labels = [clean]
        save()
        let now = Date().timeIntervalSince1970
        mutate { s in
            let miss = wasAI && changed
            s.info[photo.id] = LabelInfo(confidence: nil, source: "user", labeledAt: now, audit: miss ? "corrected" : nil)
            if miss { s.checks.append(LabelCheck(id: photo.id, kind: "corrected", at: now)) }
        }
    }

    // MARK: Auto-fix (free, server-capped path)

    private func handle(quota daily: Bool) {
        // A rejected request costs nothing, so a fixed back-off is fine.
        fix = .paused(until: Date().addingTimeInterval(daily ? 3 * 3600 : LabelHealthConst.runEvery), daily: daily)
    }

    private var isPaused: Bool {
        if case .paused(let until, _) = fix, Date() < until { return true }
        return false
    }

    /// Debounced background run — call on app open and when the photo set changes.
    func scheduleRun() {
        guard store.autoFix else { return }
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.runFix(force: false)
        }
    }

    /// One run = at most 3 requests of ≤6 photos. Priority: unlabeled → suspect → audit sample.
    /// Quota answers (402/429/503) pause quietly. Photos only, never videos.
    func runFix(force: Bool) async {
        guard let jwt = AuthManager.shared.jwt, fix != .running, !isPaused else { return }
        if !force && Date().timeIntervalSince(lastRun) < LabelHealthConst.runEvery { return }
        lastRun = Date()
        let gen = generation

        let snap = Self.snapshot(allPhotos()).filter { !$0.isVideo }
        let byId = Dictionary(uniqueKeysWithValues: snap.map { ($0.id, $0) })
        let h = LabelMetrics.compute(snap, store)
        let now = Date().timeIntervalSince1970
        let suspects = h.suspects.filter { x in
            let i = store.info[x.photo.id]
            return i == nil || now - i!.labeledAt > LabelHealthConst.relabelCooldown || i!.audit == "disagree"
        }.map { $0.photo }
        let queue = h.unlabeled + suspects
        let auditLeft = LabelHealthConst.auditPerDay - (store.auditDay == LabelMetrics.dayKey() ? store.auditCount : 0)
        if queue.isEmpty && auditLeft <= 0 { return }

        fix = .running
        var requests = 0
        var i = 0
        while i < queue.count && requests < LabelHealthConst.requestsPerRun {
            let chunk = queue[i..<min(i + LabelHealthConst.batch, queue.count)].map { (id: $0.id, relativePath: $0.path) }
            let result = await LabelService.shared.request(photos: Array(chunk), jwt: jwt, auto: true, audit: false)
            guard gen == generation else { return }
            switch result {
            case .ok(let r): applyAI(r)
            case .quota(let daily): handle(quota: daily); return
            case .failed: fix = .idle; return
            }
            i += LabelHealthConst.batch
            requests += 1
        }
        if requests < LabelHealthConst.requestsPerRun && auditLeft > 0 {
            let sample = LabelMetrics.auditSample(Self.snapshot(allPhotos()), store.info, n: min(LabelHealthConst.batch, auditLeft))
            if !sample.isEmpty {
                let items = sample.map { (id: $0.id, relativePath: $0.path) }
                let result = await LabelService.shared.request(photos: items, jwt: jwt, auto: true, audit: true)
                guard gen == generation else { return }
                switch result {
                case .ok(let r): recordAudit(r, photos: byId)
                case .quota(let daily): handle(quota: daily); return
                case .failed: fix = .idle; return
                }
            }
        }
        fix = .idle
    }

    /// "Fix now" on one photo — free path, respects pause. Returns an error message, or nil on success.
    func fixOne(_ photo: LabelPhoto) async -> String? {
        let paused = "Auto-fix is paused — daily limit reached. Try again later."
        guard !photo.isVideo else { return "Videos stay on this device." }
        guard let jwt = AuthManager.shared.jwt else { return "Sign in to fix labels." }
        if isPaused { return paused }
        switch await LabelService.shared.request(photos: [(photo.id, photo.path)], jwt: jwt, auto: true, audit: false) {
        case .ok(let r): applyAI(r); return nil
        case .quota(let daily): handle(quota: daily); return paused
        case .failed: return "Couldn't fix that label — try again."
        }
    }
}
