import SwiftUI
import SwiftData

/// Pro-only sheet. User pastes an Instagram profile URL → backend scrubs
/// public posts → Claude distills into a style description → result is
/// auto-saved to SwiftData and the user reviews + applies to AI Style Profile.
struct ScrubInstagramSheet: View {

    @Binding var currentProfile: String
    @Binding var activeScrubId: String
    @AppStorage("ai_engagement_playbook") private var enginePlaybook: String = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// Optional preloaded scrub from the library — when set, skips the network call
    /// and goes straight to review with this saved result.
    var preloadedScrub: SavedScrub? = nil

    @State private var profileURL: String = ""
    @State private var resultsLimit: Int = 12
    @State private var phase: Phase = .input
    @State private var result: ScrubService.ScrubResult? = nil
    @State private var savedRecord: SavedScrub? = nil
    @State private var errorText: String? = nil
    @State private var editableResult: String = ""
    @State private var editablePlaybook: String = ""
    @State private var activeTab: ResultTab = .style
    @State private var resolvedHandle: String = ""

    private let gold = Color(red: 200/255, green: 169/255, blue: 110/255)

    private enum Phase { case input, scrubbing, review }
    private enum ResultTab: String, CaseIterable { case style = "STYLE", playbook = "PLAYBOOK" }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 12)

                switch phase {
                case .input:
                    inputView
                case .scrubbing:
                    scrubbingView
                case .review:
                    reviewView
                }

                Spacer()
            }
            .padding(.top, 24)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .padding(20)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if let saved = preloadedScrub {
                loadFromSaved(saved)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 26, weight: .light))
                .foregroundColor(gold)
            Text("SCRUB INSTAGRAM")
                .font(.system(size: 11, weight: .black))
                .tracking(3)
                .foregroundColor(gold)
            Text("Distill an account's aesthetic into your AI Style Profile")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Input

    private var inputView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("INSTAGRAM PROFILE URL")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.4))

                TextField("https://instagram.com/username", text: $profileURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.1), lineWidth: 1))
            }
            .padding(.horizontal, 24)

            postsCountStepper

            if let errorText {
                Text(errorText)
                    .font(.system(size: 12))
                    .foregroundColor(.red.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                start()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("SCRUB & DISTILL")
                        .font(.system(size: 13, weight: .heavy))
                        .tracking(2)
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(canStart ? gold : Color.white.opacity(0.15))
                .cornerRadius(12)
            }
            .disabled(!canStart)
            .padding(.horizontal, 24)
            .padding(.top, 4)

            // Quota indicator
            let used = ScrubService.shared.usedThisMonth()
            Text("\(ScrubService.monthlyScrubLimit - used) of \(ScrubService.monthlyScrubLimit) scrubs left this month")
                .font(.system(size: 10, weight: .medium))
                .tracking(0.5)
                .foregroundColor(.white.opacity(0.3))
                .padding(.top, 6)

            Text("Public posts only. Approximately $0.05 per scrub — included with Pro.")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.25))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
                .padding(.top, 2)
        }
    }

    private var canStart: Bool {
        let trimmed = profileURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("instagram.com") && trimmed.count > 20 && ScrubService.shared.canScrub()
    }

    private var postsCountStepper: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("POSTS TO ANALYZE")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                Text(approxCost)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
            }

            HStack(spacing: 14) {
                Button { if resultsLimit > 4 { resultsLimit -= 1; HapticManager.shared.playTick() } } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(resultsLimit > 4 ? .white : .white.opacity(0.2))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .disabled(resultsLimit <= 4)

                Text("\(resultsLimit)")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(gold)
                    .frame(minWidth: 48)

                Button { if resultsLimit < 25 { resultsLimit += 1; HapticManager.shared.playTick() } } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(resultsLimit < 25 ? .white : .white.opacity(0.2))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .disabled(resultsLimit >= 25)

                Spacer()

                Text("Range: 4–25")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.25))
            }
        }
        .padding(.horizontal, 24)
    }

    private var approxCost: String {
        // Apify charges ~$0.004/post + Claude distill ~$0.003. Rough estimate.
        let dollars = Double(resultsLimit) * 0.004 + 0.003
        return String(format: "~$%.3f / scrub", dollars)
    }

    // MARK: - Scrubbing (progress)

    private var scrubbingView: some View {
        VStack(spacing: 18) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(gold)
                .scaleEffect(1.3)

            Text("Scrubbing posts & distilling style...")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))

            Text("This takes 15-30 seconds.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.25))
        }
        .padding(.vertical, 40)
    }

    // MARK: - Review (analyst report)

    private var reviewView: some View {
        ScrollView {
            VStack(spacing: 18) {
                // Receipt-style header: handle + checkmark
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 14))
                        Text("SCRUB COMPLETE")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(2)
                            .foregroundColor(.green)
                    }
                    if !resolvedHandle.isEmpty {
                        Text("@\(resolvedHandle)")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                    }
                    if let saved = savedRecord {
                        Text("Saved · \(Self.relative(saved.createdAt))")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                .padding(.top, 4)

                // Stats row
                HStack(spacing: 0) {
                    statBlock(value: "\(result?.postsAnalyzed ?? 0)", label: "POSTS\nANALYZED")
                    statDivider
                    statBlock(value: "\(result?.hashtags.count ?? 0)", label: "TOP\nHASHTAGS")
                    statDivider
                    statBlock(value: "\(editableResult.count)", label: "DESC\nCHARS")
                }
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
                .padding(.horizontal, 24)

                // Tab switcher between STYLE and PLAYBOOK
                if !(result?.engagementPlaybook ?? "").isEmpty {
                    HStack(spacing: 0) {
                        ForEach(ResultTab.allCases, id: \.self) { tab in
                            let isSel = activeTab == tab
                            Button { withAnimation(.easeOut(duration: 0.15)) { activeTab = tab } } label: {
                                Text(tab.rawValue)
                                    .font(.system(size: 11, weight: .heavy))
                                    .tracking(1.6)
                                    .foregroundColor(isSel ? gold : .white.opacity(0.45))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(
                                        Capsule()
                                            .fill(isSel ? gold.opacity(0.16) : Color.clear)
                                            .overlay(Capsule().stroke(isSel ? gold.opacity(0.45) : Color.clear, lineWidth: 1))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(3)
                    .background(Capsule().fill(Color.white.opacity(0.05)))
                    .padding(.horizontal, 24)
                }

                // Editable result content (style or playbook)
                VStack(alignment: .leading, spacing: 8) {
                    Text(activeTab == .style ? "DISTILLED STYLE" : "ENGAGEMENT PLAYBOOK")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(2)
                        .foregroundColor(gold)
                    if activeTab == .playbook {
                        Text("What WINS for this creator's audience — hooks, post types, and patterns the AI will copy.")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                            .lineSpacing(2)
                    }

                    if activeTab == .style {
                        TextEditor(text: $editableResult)
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 140, maxHeight: 200)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(gold.opacity(0.25), lineWidth: 1))
                    } else {
                        TextEditor(text: $editablePlaybook)
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 140, maxHeight: 200)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(gold.opacity(0.25), lineWidth: 1))
                    }
                }
                .padding(.horizontal, 24)

                // Top performing posts preview
                if let top = result?.topPosts, !top.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TOP POSTS")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(2)
                            .foregroundColor(.white.opacity(0.4))
                        ForEach(Array(top.prefix(3).enumerated()), id: \.offset) { idx, p in
                            HStack(alignment: .top, spacing: 8) {
                                Text("#\(idx + 1)")
                                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                    .foregroundColor(gold)
                                    .frame(width: 24, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.firstLine.isEmpty ? "[no caption]" : p.firstLine)
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.7))
                                        .lineLimit(2)
                                    Text(engagementSummary(p))
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                }

                // Hashtags
                if let tags = result?.hashtags, !tags.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TOP HASHTAGS")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(2)
                            .foregroundColor(.white.opacity(0.4))
                        FlowLayout(spacing: 6) {
                            ForEach(tags.prefix(10), id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.white.opacity(0.55))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.07))
                                    .cornerRadius(6)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                }

                // Save note (only show when this is a fresh scrub, not from library)
                if preloadedScrub == nil {
                    HStack(spacing: 6) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 9))
                        Text("Saved to your Scrub Library — re-apply anytime, free")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(gold.opacity(0.6))
                    .padding(.horizontal, 24)
                }

                // Apply buttons
                HStack(spacing: 10) {
                    Button { appendToProfile() } label: {
                        Text("APPEND")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(1.4)
                            .foregroundColor(gold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .overlay(Capsule().strokeBorder(gold.opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Button { replaceProfile() } label: {
                        Text("APPLY TO STYLE PROFILE")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(1.4)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(gold)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Report helpers

    private func statBlock(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(gold)
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.2)
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: 32)
    }

    private static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Actions

    private func start() {
        errorText = nil
        phase = .scrubbing
        let url = profileURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = resultsLimit
        Task {
            do {
                let r = try await ScrubService.shared.scrub(profileURL: url, resultsLimit: limit)
                await MainActor.run {
                    // 1. Persist to library.
                    let record = SavedScrub(
                        profileURL: url,
                        styleDescription: r.description,
                        engagementPlaybook: r.engagementPlaybook,
                        hashtags: r.hashtags,
                        postsAnalyzed: r.postsAnalyzed
                    )
                    modelContext.insert(record)
                    try? modelContext.save()

                    // 2. Show the analyst report.
                    savedRecord = record
                    result = r
                    editableResult = r.description
                    editablePlaybook = r.engagementPlaybook
                    resolvedHandle = record.handle
                    phase = .review
                    HapticManager.shared.playSuccess()
                }
            } catch {
                await MainActor.run {
                    errorText = (error as? ScrubService.ScrubError)?.message ?? error.localizedDescription
                    phase = .input
                    HapticManager.shared.playWarning()
                }
            }
        }
    }

    /// Skip network — used when reapplying a SavedScrub from the library.
    private func loadFromSaved(_ saved: SavedScrub) {
        savedRecord = saved
        editableResult = saved.styleDescription
        editablePlaybook = saved.engagementPlaybook
        resolvedHandle = saved.handle
        // Synthesize a result struct so the review view renders uniformly.
        result = ScrubService.ScrubResult(
            description: saved.styleDescription,
            engagementPlaybook: saved.engagementPlaybook,
            postsAnalyzed: saved.postsAnalyzed,
            hashtags: saved.hashtags,
            topPosts: []
        )
        phase = .review
    }

    private func replaceProfile() {
        let trimmedStyle = editableResult.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPlay  = editablePlaybook.trimmingCharacters(in: .whitespacesAndNewlines)
        currentProfile = String(trimmedStyle.prefix(750))
        enginePlaybook = String(trimmedPlay.prefix(750))
        // Mark this scrub as active when style still matches the saved record.
        if let active = savedRecord, trimmedStyle == active.styleDescription {
            activeScrubId = active.id
        } else {
            activeScrubId = ""
        }
        HapticManager.shared.playAdded()
        dismiss()
    }

    private func appendToProfile() {
        let trimmedStyle = editableResult.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPlay  = editablePlaybook.trimmingCharacters(in: .whitespacesAndNewlines)
        let combinedStyle = (currentProfile.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + trimmedStyle)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let combinedPlay = (enginePlaybook.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + trimmedPlay)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        currentProfile = String(combinedStyle.prefix(750))
        enginePlaybook = String(combinedPlay.prefix(750))
        activeScrubId = ""
        HapticManager.shared.playAdded()
        dismiss()
    }

    private func engagementSummary(_ p: ScrubService.ScrubResult.TopPost) -> String {
        var parts: [String] = []
        if p.likes > 0 { parts.append("\(formatCount(p.likes)) likes") }
        if p.comments > 0 { parts.append("\(formatCount(p.comments)) comments") }
        if p.views > 0 { parts.append("\(formatCount(p.views)) views") }
        if !p.productType.isEmpty { parts.append(p.productType) }
        return parts.joined(separator: " · ")
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}
