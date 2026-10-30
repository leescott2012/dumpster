import SwiftUI
import SwiftData
import ImageIO

// MARK: - Scan button (price + confirm) — replaces the bare "Rescan All" button

/// Shows an honest estimate before a paid Scan and requires a confirm tap.
/// Server Scan costs CreditManager.Cost.scanRequest credits per request of up to
/// Cost.scanBatchPhotos photos. Signed out → free on-device scan, no confirm of cost.
struct ScanButton: View {
    let isRescanning: Bool
    /// `useServer` false = on-device only (free).
    let onScan: (_ useServer: Bool) -> Void

    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var cs
    @ObservedObject private var credits = CreditManager.shared
    @ObservedObject private var auth = AuthManager.shared
    @Query private var photos: [DumpPhoto]
    @State private var confirm = false
    @State private var showCredits = false

    private var scannable: Int { LabelHealthManager.snapshot(photos).filter { !$0.isVideo }.count }
    private var cost: Int { CreditManager.Cost.scan(photoCount: scannable) }
    private var requests: Int { cost / CreditManager.Cost.scanRequest }
    private var canPay: Bool { credits.balance >= cost }

    var body: some View {
        Button {
            credits.refresh()
            confirm = true
        } label: {
            HStack(spacing: 5) {
                if isRescanning { ProgressView().scaleEffect(0.6).tint(appState.accentColor) }
                Text(isRescanning ? "Scanning…" : "Rescan All")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isRescanning ? Theme.text2(appState.colorMode, cs) : Theme.text(appState.colorMode, cs))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Theme.bg2(appState.colorMode, cs))
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .disabled(isRescanning || scannable == 0)
        .accessibilityLabel(auth.isSignedIn ? "Rescan all photos, about \(cost) credits" : "Rescan all photos on this device, free")
        .confirmationDialog("Scan \(scannable) photo\(scannable == 1 ? "" : "s")?", isPresented: $confirm, titleVisibility: .visible) {
            if !auth.isSignedIn {
                Button("Scan on this device (free)") { onScan(false) }
            } else if canPay {
                Button("Scan with AI · about \(cost) credits") { onScan(true) }
                Button("Scan on this device (free)") { onScan(false) }
            } else {
                Button("Get credits") { showCredits = true }
                Button("Scan on this device (free)") { onScan(false) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if !auth.isSignedIn {
                Text("Sign in to use AI labels. On-device labels are free but less specific.")
            } else if canPay {
                Text("AI scan is about \(cost) credits (\(requests) request\(requests == 1 ? "" : "s") × \(CreditManager.Cost.scanRequest)). You have \(credits.balance) credits. Videos are never scanned.")
            } else {
                Text("AI scan is about \(cost) credits and you have \(credits.balance). Get credits, or scan on this device for free.")
            }
        }
        .sheet(isPresented: $showCredits) { PaywallView().presentationDetents([.large]) }
    }
}

// MARK: - Chip

struct LabelHealthChip: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var cs
    @ObservedObject private var mgr = LabelHealthManager.shared
    @Query private var photos: [DumpPhoto]
    @State private var open = false

    private var health: LabelHealth { LabelMetrics.compute(LabelHealthManager.snapshot(photos), mgr.store) }

    var body: some View {
        let h = health
        let text = "\(h.labeled)/\(h.total) labeled" + (h.score.map { " · \($0)%" } ?? "")
        Button { open = true } label: {
            HStack(spacing: 6) {
                if mgr.fix == .running {
                    ProgressView().scaleEffect(0.5).frame(width: 8, height: 8)
                } else {
                    Circle().fill(LabelHealthSheet.dot(h.status)).frame(width: 7, height: 7)
                }
                Text(text).font(.system(size: 11)).foregroundColor(Theme.text2(appState.colorMode, cs))
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .overlay(Capsule().stroke(Theme.border2(appState.colorMode, cs), lineWidth: 1))
        }
        .accessibilityLabel("Label health: \(text). Open details")
        .sheet(isPresented: $open) { LabelHealthSheet().environmentObject(appState) }
        .task { mgr.scheduleRun() }                       // app open
        .onChange(of: photos.count) { _, _ in mgr.scheduleRun() }   // pool changed
    }
}

// MARK: - Sheet

struct LabelHealthSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var mgr = LabelHealthManager.shared
    @Query private var photos: [DumpPhoto]

    @State private var editing: String?
    @State private var cat = "LIFESTYLE"
    @State private var label = ""
    @State private var busy: String?
    @State private var message: String?

    private let gold = Color(hex: "#C8A96E")

    static func dot(_ s: LabelHealth.Status) -> Color {
        switch s {
        case .green: return Color(red: 0.13, green: 0.77, blue: 0.37)
        case .amber: return Color(red: 0.96, green: 0.62, blue: 0.04)
        case .red: return Color(red: 0.94, green: 0.27, blue: 0.27)
        }
    }

    private func fixNote(_ f: LabelHealthManager.FixStatus) -> String? {
        switch f {
        case .running: return "Fixing…"
        case .paused(let until, let daily): return Date() < until ? (daily ? "Paused — daily limit" : "Paused — resumes in a few minutes") : nil
        case .idle: return nil
        }
    }

    private func title(_ c: String) -> String { c.isEmpty ? "—" : c.prefix(1).uppercased() + c.dropFirst().lowercased() }

    var body: some View {
        let snap = LabelHealthManager.snapshot(photos)
        let h = LabelMetrics.compute(snap, mgr.store)
        let items: [(photo: LabelPhoto, reason: SuspectReason)] =
            h.unlabeled.map { ($0, SuspectReason.unlabeled) } + h.suspects.map { ($0.photo, $0.reason) }
        let pct = Int((h.coverage * 100).rounded())

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(fixNote(mgr.fix) ?? "Photos only — videos stay on this device")
                        .font(.system(size: 11)).foregroundColor(.white.opacity(0.5))

                    // Coverage
                    HStack {
                        Text("Labeled").font(.system(size: 12)).foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text("\(h.labeled) of \(h.total) (\(pct)%)").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                    }
                    ProgressView(value: h.coverage).tint(Self.dot(h.status))
                        .accessibilityLabel("Photos labeled").accessibilityValue("\(pct) percent")
                    Text(confidenceLine(snap))
                        .font(.system(size: 11)).foregroundColor(.white.opacity(0.5))

                    // Accuracy
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Accuracy").font(.system(size: 12)).foregroundColor(.white.opacity(0.7))
                            Spacer()
                            if let s = h.score { Text("\(s)%").font(.system(size: 22, weight: .bold)).foregroundColor(.white) }
                            else { Text("Not enough data yet").font(.system(size: 13, weight: .bold)).foregroundColor(.white) }
                        }
                        Text(h.score != nil ? "Based on \(h.basis) checks" : "\(h.basis) of \(LabelHealthConst.minChecksForScore) checks needed")
                            .font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
                        DisclosureGroup {
                            Text("Every time you tap \"Looks right\" on an AI label it counts as a hit; every time you change an AI label it counts as a miss. Those count double. A few photos a day also get a second, independent AI look — if it picks the same category that's a hit, otherwise a miss. The score is hits divided by all checks. We only show it after \(LabelHealthConst.minChecksForScore) checks so it isn't a guess.")
                                .font(.system(size: 11)).foregroundColor(.white.opacity(0.5)).lineSpacing(3)
                        } label: {
                            Text("How is this scored?").font(.system(size: 11)).foregroundColor(gold)
                        }
                        .tint(gold)
                    }
                    .padding(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 1))

                    // Controls
                    if mgr.freeUsed {
                        Text("Your free first scan is used up. New photos are labeled only when you tap Scan (1 credit per photo).")
                            .font(.system(size: 12)).foregroundColor(.white.opacity(0.75))
                    } else {
                    HStack {
                        Toggle("Free first scan (auto)", isOn: Binding(get: { mgr.store.autoFix }, set: { mgr.setAutoFix($0) }))
                            .font(.system(size: 12)).tint(gold)
                        Button {
                            Task { await mgr.runFix(force: true) }
                        } label: {
                            Label(mgr.fix == .running ? "Fixing…" : "Scan free now", systemImage: "wand.and.stars")
                                .font(.system(size: 11, weight: .bold)).foregroundColor(.black)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Capsule().fill(gold))
                        }
                        .disabled(mgr.fix == .running)
                    }
                    }
                    if let message { Text(message).font(.system(size: 11)).foregroundColor(gold) }

                    // Needs attention
                    Text(items.isEmpty ? "ALL GOOD" : "NEEDS ATTENTION (\(items.count))")
                        .font(.system(size: 11, weight: .bold)).tracking(2).foregroundColor(.white.opacity(0.5)).padding(.top, 6)
                    if items.isEmpty {
                        Text("Every photo has a specific label.").font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                    }
                    ForEach(items.prefix(60), id: \.photo.id) { it in row(it.photo, it.reason) }
                    if items.count > 60 {
                        Text("+\(items.count - 60) more — Auto-fix works through them in the background.")
                            .font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
                    }
                }
                .padding(20)
            }
            .background(Color(white: 0.05).ignoresSafeArea())
            .navigationTitle("Label Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
    }

    private func subtitle(_ p: LabelPhoto, _ reason: SuspectReason, _ conf: Double?) -> String {
        var out = ""
        if !p.category.isEmpty { out += title(p.category) + " · " }
        out += reason.rawValue
        if let c = conf { out += " · \(Int((c * 100).rounded()))% sure" }
        return out
    }

    private func confidenceLine(_ snap: [LabelPhoto]) -> String {
        var hi = 0, med = 0, low = 0, unk = 0
        for (p, s) in LabelMetrics.classify(snap, mgr.store.info) {
            if case .unlabeled = s { continue }
            guard let c = mgr.store.info[p.id]?.confidence else { unk += 1; continue }
            if c >= 0.85 { hi += 1 } else if c >= LabelHealthConst.lowConfidence { med += 1 } else { low += 1 }
        }
        return "AI confidence: \(hi) high · \(med) medium · \(low) low" + (unk > 0 ? " · \(unk) older (no score)" : "")
    }

    @ViewBuilder
    private func row(_ p: LabelPhoto, _ reason: SuspectReason) -> some View {
        let conf = mgr.store.info[p.id]?.confidence
        HStack(alignment: .top, spacing: 10) {
            Thumb(path: p.path).frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                if editing == p.id {
                    Picker("Category", selection: $cat) {
                        ForEach(LabelHealthConst.categories, id: \.self) { Text(title($0)).tag($0) }
                    }
                    .pickerStyle(.menu).tint(gold)
                    TextField("e.g. Red G-Wagon", text: $label)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: label) { _, v in if v.count > 60 { label = String(v.prefix(60)) } }
                    HStack {
                        pill("Save", "checkmark") {
                            mgr.edit(p, category: cat, label: label)
                            editing = nil
                        }.disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
                        pill("Cancel", "xmark") { editing = nil }
                    }
                } else {
                    Text(LabelMetrics.isGeneric(p.alt) ? "No label yet" : p.alt)
                        .font(.system(size: 13)).foregroundColor(.white).lineLimit(1)
                    Text(subtitle(p, reason, conf))
                        .font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
                    HStack {
                        pill("Fix now", busy == p.id ? "hourglass" : "wand.and.stars") {
                            busy = p.id
                            Task {
                                message = await mgr.fixOne(p)
                                busy = nil
                            }
                        }.disabled(busy == p.id)
                        if reason != .unlabeled {
                            pill("Looks right", "checkmark") { mgr.verify(p.id) }
                        }
                        pill("Edit", "pencil") {
                            editing = p.id
                            cat = LabelMetrics.isValidCategory(p.category) ? p.category.uppercased() : "LIFESTYLE"
                            label = LabelMetrics.isGeneric(p.alt) ? "" : p.alt
                        }
                    }
                }
            }
        }
        .padding(.bottom, 8)
    }

    private func pill(_ text: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(text, systemImage: icon).font(.system(size: 11)).foregroundColor(.white.opacity(0.75))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
        }
    }
}

/// Small downsampled thumbnail straight from disk (never decodes the full image).
private struct Thumb: View {
    let path: String
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Rectangle().fill(Color.white.opacity(0.08)) }
        }
        .task(id: path) {
            let p = path
            image = await Task.detached(priority: .utility) { () -> UIImage? in
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let opts = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceThumbnailMaxPixelSize: 160,
                            kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary
                guard let src = CGImageSourceCreateWithURL(docs.appendingPathComponent(p) as CFURL, nil),
                      let t = CGImageSourceCreateThumbnailAtIndex(src, 0, opts) else { return nil }
                return UIImage(cgImage: t)
            }.value
        }
    }
}
