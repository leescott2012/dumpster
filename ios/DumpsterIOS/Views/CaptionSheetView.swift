import SwiftUI
import SwiftData

// MARK: - Tone (same four options and copy as web CaptionSheet)

enum CaptionTone: String, CaseIterable, Identifiable {
    case aesthetic, minimal, witty, poetic
    var id: String { rawValue }

    var label: String {
        switch self {
        case .aesthetic: return "Aesthetic"
        case .minimal:   return "Minimal"
        case .witty:     return "Witty"
        case .poetic:    return "Poetic"
        }
    }
    var hint: String {
        switch self {
        case .aesthetic: return "On-brand, scroll-stopping"
        case .minimal:   return "One line, no fluff"
        case .witty:     return "Clever, wordplay"
        case .poetic:    return "Evocative, imagery"
        }
    }
    /// Value /api/ai-caption expects ("default" = Aesthetic).
    var serverValue: String { self == .aesthetic ? "default" : rawValue }
    var promptModifier: String {
        switch self {
        case .aesthetic: return "Write aesthetic, on-brand Instagram captions."
        case .minimal:   return "Write extremely short, minimal captions. One line max."
        case .witty:     return "Write clever, witty captions with wordplay."
        case .poetic:    return "Write poetic, evocative captions with imagery."
        }
    }
}

// MARK: - CaptionSheetView
//
// Native twin of web CaptionSheet.tsx: pick a dump, say what the caption is about,
// tweak title/category, choose a tone, generate 3 captions (server path costs 3 credits,
// charged by the server), then Use / copy / Regenerate. Results are saved to the dump
// as DumpCaption rows (style "ai") and shown in the caption bubble on the dump card.

struct CaptionSheetView: View {
    let initialDumpID: String
    let allPhotos: [DumpPhoto]
    let tasteExamples: [AITasteExample]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PhotoDump.num) private var allDumps: [PhotoDump]

    private enum Phase { case picker, loading, result, error }

    @State private var phase: Phase = .picker
    @State private var selectedID: String = ""
    @State private var tone: CaptionTone = .aesthetic
    @State private var about = ""
    @State private var titleOverride = ""
    @State private var categoryOverride = ""
    @State private var captions: [String] = []
    @State private var vibe = ""
    @State private var errorMsg = ""
    @State private var copiedIdx: Int?
    @State private var usedIdx = 0

    private let blue = Color(hex: "#6E8EC8")
    private let gold = Color(hex: "#C8A96E")
    private let card = Color(white: 0.08)
    private let line = Color(white: 0.12)

    private var dumps: [PhotoDump] { allDumps.filter { !$0.archived } }
    private var selectedDump: PhotoDump? { dumps.first { $0.id == selectedID } }
    /// Server AI costs credits; an own provider key is free.
    private var chargesCredits: Bool { !LLMService.shared.hasAnyAPIKey }
    private var costLabel: String { chargesCredits ? " · \(CreditManager.Cost.aiCaption) credits" : "" }

    private func photos(of dump: PhotoDump) -> [DumpPhoto] {
        let byID = Dictionary(allPhotos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return dump.photoIDs.compactMap { byID[$0] }
    }

    /// Most common category in the dump (auto-detected default, like web).
    private func detectedCategory(of dump: PhotoDump) -> String {
        photos(of: dump).map(\.category)
            .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
            .max { $0.value < $1.value }?.key ?? ""
    }

    private var tasteBlock: String {
        AITasteExample.promptBlock(from: tasteExamples) + AITasteExample.captionVoiceBlock()
    }
    private var tasteActive: Bool {
        !LLMService.shared.userContextBlock(tasteBlock: tasteBlock).isEmpty
    }

    var body: some View {
        ZStack {
            card.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Divider().background(line)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if dumps.isEmpty {
                            Text("Create a dump first, then come back to caption it.")
                                .font(.system(size: 13)).foregroundColor(.white.opacity(0.5))
                                .frame(maxWidth: .infinity).padding(.vertical, 32)
                        } else {
                            switch phase {
                            case .picker:  pickerBody
                            case .loading: loadingBody
                            case .error:   errorBody
                            case .result:  resultBody
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            selectedID = initialDumpID
            reseedFields()
        }
        .onChange(of: selectedID) { _, _ in reseedFields() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "textformat")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(blue)
                .frame(width: 32, height: 32)
                .background(blue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(blue.opacity(0.3), lineWidth: 1))
            VStack(alignment: .leading, spacing: 1) {
                Text("AI Captions").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                Text("Claude Haiku").font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
                    .frame(width: 32, height: 32)
                    .background(Color(white: 0.1))
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 14)
    }

    private func sectionLabel(_ text: String, optional: Bool = false) -> some View {
        (Text(text.uppercased()).font(.system(size: 11, weight: .bold)).tracking(1.1)
            + Text(optional ? "  (optional)" : "").font(.system(size: 11)).foregroundColor(.white.opacity(0.3)))
            .foregroundColor(.white.opacity(0.5))
            .padding(.bottom, 12)
    }

    // MARK: Picker

    private var pickerBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Choose a dump")
            VStack(spacing: 8) {
                ForEach(dumps) { d in dumpRow(d) }
            }
            .padding(.bottom, 24)

            sectionLabel("What's the caption about?", optional: true)
            TextField("Tell Claude the mood, the joke, the story — or leave blank to let the photos speak.",
                      text: $about, axis: .vertical)
                .lineLimit(3...6)
                .font(.system(size: 13))
                .foregroundColor(Color(white: 0.9))
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Color(white: 0.13))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                .padding(.bottom, 20)

            HStack(alignment: .top, spacing: 10) {
                smallField("Title", text: $titleOverride, placeholder: selectedDump?.title ?? "Dump title")
                smallField("Category", text: $categoryOverride,
                           placeholder: selectedDump.map(detectedCategory(of:)).flatMap { $0.isEmpty ? nil : $0 } ?? "e.g. fashion, food")
            }
            .padding(.bottom, 24)

            sectionLabel("Tone")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(CaptionTone.allCases) { t in toneCard(t) }
            }
            .padding(.bottom, 24)

            if tasteActive {
                HStack(spacing: 5) {
                    Circle().fill(blue).frame(width: 5, height: 5)
                    Text("TASTE PROFILE ACTIVE")
                        .font(.system(size: 10, weight: .bold)).tracking(1.0).foregroundColor(blue)
                }
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(blue.opacity(0.08))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(blue.opacity(0.25), lineWidth: 1))
                .padding(.bottom, 12)
            }

            Button { Task { await generate() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").font(.system(size: 14))
                    Text("Generate Captions\(costLabel)").font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(selectedDump == nil ? .white.opacity(0.25) : .black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(selectedDump == nil ? Color(white: 0.1) : gold)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(selectedDump == nil)
        }
    }

    private func dumpRow(_ d: PhotoDump) -> some View {
        let active = d.id == selectedID
        let ps = photos(of: d).prefix(3)
        return Button { selectedID = d.id } label: {
            HStack(spacing: 12) {
                HStack(spacing: 2) {
                    ForEach(Array(ps), id: \.id) { p in
                        Group {
                            if let img = PhotoStorageManager.shared.thumbnail(relativePath: p.localPath, maxPixel: 80) {
                                Image(uiImage: img).resizable().scaledToFill()
                            } else {
                                Color(white: 0.15)
                            }
                        }
                        .frame(width: 24, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(d.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(active ? gold : Color(white: 0.9))
                        .lineLimit(1)
                    if hasSavedCaptions(d) {
                        Text("Captions saved").font(.system(size: 11)).foregroundColor(.white.opacity(0.35))
                    }
                }
                Spacer(minLength: 0)
                if active {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .heavy)).foregroundColor(.black)
                        .frame(width: 18, height: 18).background(gold).clipShape(Circle())
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(active ? gold.opacity(0.08) : Color(white: 0.13))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(active ? gold.opacity(0.35) : Color.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func smallField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold)).tracking(1.0).foregroundColor(.white.opacity(0.5))
            TextField(placeholder, text: text)
                .font(.system(size: 12))
                .foregroundColor(Color(white: 0.9))
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Color(white: 0.13))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toneCard(_ t: CaptionTone) -> some View {
        let active = tone == t
        return Button { tone = t } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(t.label).font(.system(size: 12, weight: .bold)).foregroundColor(active ? blue : Color(white: 0.9))
                Text(t.hint).font(.system(size: 10)).foregroundColor(.white.opacity(0.35))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(active ? blue.opacity(0.1) : Color(white: 0.13))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(active ? blue.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Loading / error

    private var loadingBody: some View {
        VStack(spacing: 6) {
            ProgressView().controlSize(.large).tint(gold).padding(.bottom, 10)
            Text("Writing captions...").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
            Text("Claude is finding the right voice for \"\(selectedDump?.title ?? "")\"")
                .font(.system(size: 12)).foregroundColor(.white.opacity(0.4)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    private var errorBody: some View {
        VStack(spacing: 20) {
            Text(errorMsg)
                .font(.system(size: 13, weight: .bold)).foregroundColor(Color(red: 0.94, green: 0.27, blue: 0.27))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18).padding(.vertical, 14)
                .background(Color(red: 0.94, green: 0.27, blue: 0.27).opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(red: 0.94, green: 0.27, blue: 0.27).opacity(0.2), lineWidth: 1))
            Button { Task { await generate() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 13))
                    Text("Try Again").font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(gold)
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(Color(white: 0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            }
        }
        .padding(.vertical, 28)
    }

    // MARK: Result

    private var resultBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(blue).frame(width: 6, height: 6)
                Text("VIBE · \(vibe)".uppercased())
                    .font(.system(size: 10, weight: .bold)).tracking(1.0).foregroundColor(blue)
            }
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(blue.opacity(0.1))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(blue.opacity(0.25), lineWidth: 1))
            .padding(.bottom, 16)

            Text("Saved to \"\(selectedDump?.title ?? "")\". \"Use\" picks the caption that's shared first.")
                .font(.system(size: 11)).foregroundColor(.white.opacity(0.5)).padding(.bottom, 12)

            VStack(spacing: 10) {
                ForEach(Array(captions.enumerated()), id: \.offset) { i, cap in captionRow(i, cap) }
            }
            .padding(.bottom, 18)

            HStack(spacing: 10) {
                Button { phase = .picker } label: {
                    Text("Pick Another Dump")
                        .font(.system(size: 13, weight: .medium)).foregroundColor(.white.opacity(0.55))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Color(white: 0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                }
                Button { Task { await generate() } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 13))
                        Text(chargesCredits ? "Regenerate · \(CreditManager.Cost.aiCaption)" : "Regenerate")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(gold)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(gold.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(gold.opacity(0.3), lineWidth: 1))
                }
            }
        }
    }

    private func captionRow(_ i: Int, _ cap: String) -> some View {
        let inUse = usedIdx == i
        let green = Color(red: 0.13, green: 0.77, blue: 0.37)
        return HStack(alignment: .top, spacing: 12) {
            // Caption OPTION number (1-3), not a photo number.
            Text("\(i + 1)")
                .font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.55))
                .frame(width: 20, height: 20)
                .background(Color(white: 0.1))
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                .padding(.top, 1)
            Text(cap)
                .font(.system(size: 14)).lineSpacing(3).foregroundColor(Color(white: 0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { use(i) } label: {
                Text(inUse ? "In use" : "Use")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(inUse ? green : Color(white: 0.8))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(inUse ? green.opacity(0.12) : Color(white: 0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(inUse ? green.opacity(0.35) : Color.white.opacity(0.12), lineWidth: 1))
            }
            .disabled(inUse)
            Button {
                UIPasteboard.general.string = cap
                copiedIdx = i
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if copiedIdx == i { copiedIdx = nil } }
            } label: {
                Image(systemName: copiedIdx == i ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 13))
                    .foregroundColor(copiedIdx == i ? green : .white.opacity(0.5))
                    .frame(width: 24, height: 24)
            }
            .accessibilityLabel("Copy caption")
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Color(white: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: Logic

    private func reseedFields() {
        guard let d = selectedDump else { return }
        titleOverride = d.title
        categoryOverride = detectedCategory(of: d)
    }

    private func hasSavedCaptions(_ d: PhotoDump) -> Bool {
        let id: String? = d.id
        let f = FetchDescriptor<DumpCaption>(predicate: #Predicate { $0.dumpId == id && !$0.deleted })
        return ((try? modelContext.fetchCount(f)) ?? 0) > 0
    }

    @MainActor
    private func generate() async {
        guard let dump = selectedDump else { return }
        // No own key and signed out: the server can't be used (web gets a 401 here).
        guard LLMService.shared.hasAnyAPIKey || LLMService.ServerAI.isAvailable else {
            errorMsg = "Sign in to use AI captions."
            phase = .error
            return
        }
        phase = .loading
        errorMsg = ""

        var seen = Set<String>()
        let labels = photos(of: dump).flatMap { $0.promptLabels }
            .filter { seen.insert($0).inserted }
            .prefix(20).map { $0 }
        let title = titleOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = categoryOverride.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let result = try await LLMService.shared.generateCaption(
                for: title.isEmpty ? dump.title : title,
                category: category.isEmpty ? detectedCategory(of: dump) : category,
                tasteBlock: tasteBlock,
                labels: labels,
                tone: tone,
                about: about
            )
            let caps = result.captions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }.prefix(3).map { $0 }
            guard !caps.isEmpty else {
                errorMsg = "Couldn't write captions this time. Try again."
                phase = .error
                return
            }
            save(caps, vibe: result.vibe, to: dump)
            captions = caps
            vibe = result.vibe
            usedIdx = 0
            HapticManager.shared.playSuccess()
            phase = .result
        } catch {
            errorMsg = FriendlyError.message(for: error, tags: ["op": "caption_generate", "dumpId": dump.id])
            phase = .error
        }
    }

    /// Replace the dump's previous AI captions with the new set (web does the same), newest set first.
    private func save(_ caps: [String], vibe: String, to dump: PhotoDump) {
        let id: String? = dump.id
        let old = (try? modelContext.fetch(FetchDescriptor<DumpCaption>(
            predicate: #Predicate { $0.dumpId == id && !$0.deleted && $0.style == "ai" }))) ?? []
        for c in old { c.deleted = true }
        let base = Date()
        for (i, text) in caps.enumerated() {
            let c = DumpCaption(text: text, style: "ai", dumpId: dump.id)
            c.createdAt = base.addingTimeInterval(Double(i) * 0.001)   // bubble sorts oldest-first
            modelContext.insert(c)
        }
        dump.vibe = vibe
        try? modelContext.save()
    }

    /// "Use": move the chosen caption to the front of the dump's captions (the one shared first).
    private func use(_ i: Int) {
        guard let dump = selectedDump, captions.indices.contains(i) else { return }
        let id: String? = dump.id
        let text = captions[i]
        let rows = (try? modelContext.fetch(FetchDescriptor<DumpCaption>(
            predicate: #Predicate { $0.dumpId == id && !$0.deleted }))) ?? []
        if let chosen = rows.first(where: { $0.text == text }),
           let earliest = rows.map(\.createdAt).min() {
            chosen.createdAt = earliest.addingTimeInterval(-1)
            try? modelContext.save()
        }
        usedIdx = i
        HapticManager.shared.playTick()
    }
}
