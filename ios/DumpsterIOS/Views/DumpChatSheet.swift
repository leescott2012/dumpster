import SwiftUI
import SwiftData

struct DumpChatSheet: View {

    let dump: PhotoDump
    let dumpPhotos: [DumpPhoto]
    let poolPhotos: [DumpPhoto]
    let tasteExamples: [AITasteExample]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: AppState

    @State private var messages: [DumpChatMessage] = []
    @State private var input = ""
    @State private var isLoading = false
    @State private var errorText: String?

    private let gold = Color(hex: "#C8A96E")

    var body: some View {
        ZStack {
            Color(white: 0.05).ignoresSafeArea()

            VStack(spacing: 0) {
                dragHandle
                header
                photoStrip
                Divider().background(Color.white.opacity(0.07))
                messageList
                inputBar
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .onAppear(perform: loadHistory)
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        Capsule()
            .fill(Color.white.opacity(0.2))
            .frame(width: 36, height: 4)
            .padding(.top, 12)
            .padding(.bottom, 8)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 10)
                .fill(gold.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(gold.opacity(0.25), lineWidth: 1)
                )
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundColor(gold)
                )
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("Valet · \(dump.title)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("\(dumpPhotos.count) photos\(dump.vibeBadge.map { " · \($0)" } ?? "")")
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.35))
            }

            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(white: 0.4))
                    .frame(width: 32, height: 32)
                    .background(Color(white: 0.1))
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color(white: 0.15), lineWidth: 1))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    // MARK: - Photo Strip

    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if dumpPhotos.isEmpty {
                    Text("Empty dump — tell me what to pull from the pool")
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.27))
                        .padding(.vertical, 12)
                } else {
                    ForEach(Array(dumpPhotos.enumerated()), id: \.element.id) { idx, photo in
                        ZStack(alignment: .bottomTrailing) {
                            if let img = loadImage(photo) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 48, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(Color(white: 0.17), lineWidth: 1)
                                    )
                            } else {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(white: 0.12))
                                    .frame(width: 48, height: 48)
                            }
                            Text("\(idx + 1)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white.opacity(0.6))
                                .padding(2)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if messages.isEmpty {
                        emptyState
                    }

                    ForEach(messages, id: \.id) { msg in
                        MessageBubble(message: msg, accentColor: gold)
                            .id(msg.id)
                    }

                    if isLoading {
                        loadingBubble
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("✨")
                .font(.system(size: 28))
                .padding(.top, 32)
            Text("Ask the Valet about this dump")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(white: 0.9))
            Text("Tell me what vibe you want, which photos to lead with, what to swap out. I learn your taste over time.")
                .font(.system(size: 12))
                .foregroundColor(Color(white: 0.35))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 280)

            quickPrompts
                .padding(.top, 8)
        }
        .padding(.bottom, 20)
    }

    private var quickPrompts: some View {
        let prompts = [
            "make this feel like a saturday night",
            "lead with the strongest photo",
            "too many similar shots",
            "pull something moody from the pool",
        ]
        return FlowLayout(spacing: 6) {
            ForEach(prompts, id: \.self) { prompt in
                Button { input = prompt } label: {
                    Text(prompt)
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.6))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(gold.opacity(0.06))
                        .overlay(
                            Capsule().strokeBorder(gold.opacity(0.15), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var loadingBubble: some View {
        HStack {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(gold)
                Text("thinking...")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(white: 0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color(white: 0.15), lineWidth: 1)
            )
            Spacer()
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Tell me what to change...", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .font(.system(size: 13))
                .foregroundColor(Color(white: 0.9))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(white: 0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color(white: 0.15), lineWidth: 1)
                )
                .onSubmit { sendMessage() }

            Button(action: sendMessage) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(canSend ? .black : Color(white: 0.27))
                    .frame(width: 44, height: 44)
                    .background(canSend ? gold : Color(white: 0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(canSend ? gold : Color(white: 0.15), lineWidth: 1)
                    )
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 40)
        .background(Color(white: 0.05))
        .overlay(alignment: .top) {
            Divider().background(Color.white.opacity(0.07))
        }
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    // MARK: - Logic

    private func loadHistory() {
        let dumpId = dump.id
        let descriptor = FetchDescriptor<DumpChatMessage>(
            predicate: #Predicate { $0.dumpId == dumpId },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        messages = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func sendMessage() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }
        input = ""
        errorText = nil

        let userMsg = DumpChatMessage(dumpId: dump.id, role: "user", text: text)
        modelContext.insert(userMsg)
        messages.append(userMsg)
        try? modelContext.save()

        isLoading = true

        Task {
            do {
                let chatPhotos = dumpPhotos.map {
                    LLMService.ChatPhoto(id: $0.id, category: $0.category, labels: $0.labels)
                }
                let chatPool = poolPhotos.map {
                    LLMService.ChatPhoto(id: $0.id, category: $0.category, labels: $0.labels)
                }
                let history = messages.filter { $0.role == "user" || $0.role == "assistant" }
                    .dropLast()
                    .map { LLMService.ChatHistoryMessage(role: $0.role, text: $0.text) }

                let taste = AITasteExample.promptBlock(from: tasteExamples)

                let response = try await LLMService.shared.chatWithDump(
                    dumpTitle: dump.title,
                    dumpPhotos: chatPhotos,
                    poolPhotos: chatPool,
                    history: Array(history),
                    message: text,
                    vibe: dump.vibeBadge,
                    tasteBlock: taste
                )

                executeActions(response.actions)

                let actionsData = try? JSONEncoder().encode(response.actions)
                let actionsJSON = actionsData.flatMap { String(data: $0, encoding: .utf8) }

                let assistantMsg = DumpChatMessage(
                    dumpId: dump.id,
                    role: "assistant",
                    text: response.reply,
                    actionsJSON: actionsJSON
                )
                modelContext.insert(assistantMsg)
                messages.append(assistantMsg)
                try? modelContext.save()

                HapticManager.shared.playTick()
            } catch {
                let errMsg = DumpChatMessage(
                    dumpId: dump.id,
                    role: "assistant",
                    text: "Sorry, I hit an error: \(error.localizedDescription)"
                )
                modelContext.insert(errMsg)
                messages.append(errMsg)
                try? modelContext.save()
            }

            isLoading = false
        }
    }

    private func executeActions(_ actions: [LLMService.ChatAction]) {
        for action in actions {
            switch action.type {
            case "reorder":
                if let ids = action.photoIds {
                    let validIds = ids.filter { id in dumpPhotos.contains { $0.id == id } }
                    if !validIds.isEmpty {
                        dump.photoIDs = validIds
                    }
                }
            case "swap_in":
                if let photoId = action.photoId,
                   poolPhotos.contains(where: { $0.id == photoId }),
                   dump.photoIDs.count < 20 {
                    let pos = min(action.position ?? dump.photoIDs.count, dump.photoIDs.count)
                    dump.photoIDs.insert(photoId, at: pos)
                }
            case "swap_out":
                if let idx = action.index, idx >= 0, idx < dump.photoIDs.count {
                    dump.photoIDs.remove(at: idx)
                }
            case "update_vibe":
                if let vibe = action.vibe {
                    dump.vibeBadge = vibe
                }
            case "taste_update":
                if let pref = action.preference {
                    let current = UserDefaults.standard.string(forKey: "ai_style_profile") ?? ""
                    let updated = current.isEmpty ? pref : current + "\n" + pref
                    UserDefaults.standard.set(updated, forKey: "ai_style_profile")
                }
            default:
                break
            }
        }
        try? modelContext.save()
    }

    private func loadImage(_ photo: DumpPhoto) -> UIImage? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent(photo.localPath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: DumpChatMessage
    let accentColor: Color

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 0) {
                Text(message.text)
                    .font(.system(size: 13))
                    .foregroundColor(isUser ? Color(white: 0.9) : Color(white: 0.8))
                    .lineSpacing(4)

                if !missingItems.isEmpty {
                    Divider()
                        .background(Color.white.opacity(0.06))
                        .padding(.vertical, 8)
                    missingItemsCard
                }

                if let chips = actionChips, !chips.isEmpty {
                    Divider()
                        .background(Color.white.opacity(0.06))
                        .padding(.vertical, 8)
                    FlowLayout(spacing: 4) {
                        ForEach(chips, id: \.label) { chip in
                            HStack(spacing: 4) {
                                Image(systemName: chip.icon)
                                    .font(.system(size: 9))
                                Text(chip.label)
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(chip.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(chip.color.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(chip.color.opacity(0.2), lineWidth: 1)
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isUser ? accentColor.opacity(0.12) : Color(white: 0.1))
            .clipShape(
                RoundedRectangle(cornerRadius: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isUser ? accentColor.opacity(0.25) : Color(white: 0.15),
                        lineWidth: 1
                    )
            )
            if !isUser { Spacer(minLength: 40) }
        }
    }

    private struct ActionChip: Hashable {
        let icon: String
        let label: String
        let color: Color
    }

    private var decodedActions: [LLMService.ChatAction] {
        guard let json = message.actionsJSON,
              let data = json.data(using: .utf8),
              let actions = try? JSONDecoder().decode([LLMService.ChatAction].self, from: data) else {
            return []
        }
        return actions
    }

    private var missingItems: [LLMService.ChatAction.MissingItem] {
        decodedActions.filter { $0.type == "suggest_missing" }.flatMap { $0.items ?? [] }
    }

    private var missingItemsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TO COMPLETE THIS VIBE")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundColor(accentColor)

            ForEach(Array(missingItems.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: item.inPool ? "photo.on.rectangle" : "camera")
                        .font(.system(size: 11))
                        .foregroundColor(accentColor.opacity(0.8))
                        .frame(width: 16)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.description)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(white: 0.85))
                        Text(item.reason)
                            .font(.system(size: 11))
                            .foregroundColor(Color(white: 0.45))
                            .lineSpacing(3)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(accentColor.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(accentColor.opacity(0.15), lineWidth: 1)
                )
            }
        }
    }

    private var actionChips: [ActionChip]? {
        return decodedActions.compactMap { action in
            switch action.type {
            case "reorder":      return ActionChip(icon: "arrow.up.arrow.down", label: "Reordered", color: Color(hex: "#C8A96E"))
            case "swap_in":      return ActionChip(icon: "arrow.down.to.line", label: "Added from pool", color: Color(hex: "#4ADE80"))
            case "swap_out":     return ActionChip(icon: "arrow.up.forward", label: "Sent to pool", color: Color(hex: "#F97316"))
            case "update_vibe":  return ActionChip(icon: "paintpalette", label: "Vibe updated", color: Color(hex: "#A78BFA"))
            case "taste_update": return ActionChip(icon: "brain", label: "Remembered", color: Color(hex: "#6EE7B7"))
            default:             return nil
            }
        }
    }
}

// MARK: - Flow Layout

private struct DumpChatFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
