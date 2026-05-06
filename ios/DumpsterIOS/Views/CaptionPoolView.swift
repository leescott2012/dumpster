import SwiftUI
import SwiftData

/// Caption library view with style chips, auto-generate, custom entry, and filter tabs.
struct CaptionPoolView: View {

    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var cs

    @Query(sort: \DumpCaption.createdAt, order: .reverse) private var allCaptions: [DumpCaption]

    @State private var selectedStyle: String = "storytelling"
    @State private var customText: String = ""
    @State private var captionTab: CaptionTab = .all

    enum CaptionTab: String, CaseIterable, Identifiable {
        case all, favorites, banned
        var id: String { rawValue }
    }

    private let styles: [(key: String, label: String)] = [
        ("storytelling", "Storytelling"),
        ("emoji",        "Emoji"),
        ("clean",        "Clean"),
        ("numbered",     "Numbered")
    ]

    static let templateBanks: [String: [String]] = [
        "storytelling": [
            "the kind of night you tell stories about",
            "we didn't plan this, it just happened",
            "somewhere between the chaos and the calm",
            "a collection of moments I refuse to forget",
            "the unfiltered version of last week"
        ],
        "emoji": [
            "📸✨🔥",
            "🌙💫🖤",
            "🏎💨✨"
        ],
        "clean": [
            "recent.",
            "documented.",
            "filed under: good times"
        ],
        "numbered": [
            "1. showed up  2. showed out",
            "1/10 of why this week hit different"
        ]
    ]

    private var filteredCaptions: [DumpCaption] {
        switch captionTab {
        case .all:       return allCaptions
        case .favorites: return allCaptions.filter { $0.favorited }
        case .banned:    return allCaptions.filter { $0.banned }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            styleChips
            actionRow
            customEntry
            tabRow
            captionList
        }
        .background(Theme.bg(appState.colorMode, cs).ignoresSafeArea())
    }

    private var header: some View {
        HStack {
            Text("CAPTION POOL")
                .font(.system(size: 11, weight: .heavy))
                .tracking(2.0)
                .foregroundColor(appState.accentColor)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private var styleChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(styles, id: \.key) { style in
                    let isSel = style.key == selectedStyle
                    Text(style.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isSel ? .black : Theme.text(appState.colorMode, cs))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isSel ? appState.accentColor : Theme.bg2(appState.colorMode, cs))
                        .clipShape(Capsule())
                        .onTapGesture { selectedStyle = style.key }
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private var actionRow: some View {
        HStack {
            Button(action: autoGenerate) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text("Auto-Generate")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(appState.accentColor)
                .clipShape(Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, 12)
    }

    private func autoGenerate() {
        guard let bank = Self.templateBanks[selectedStyle], !bank.isEmpty else { return }
        let existing = Set(allCaptions.map { $0.text })
        let candidates = bank.filter { !existing.contains($0) }
        let pick = candidates.randomElement() ?? bank.randomElement()!
        let cap = DumpCaption(text: pick, style: selectedStyle, dumpId: appState.activeDumpId)
        modelContext.insert(cap)
        try? modelContext.save()
    }

    private var customEntry: some View {
        HStack {
            TextField("Add a custom caption…", text: $customText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(Theme.text(appState.colorMode, cs))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Theme.bg2(appState.colorMode, cs))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Button {
                let trimmed = customText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                let cap = DumpCaption(text: trimmed, style: selectedStyle, dumpId: appState.activeDumpId)
                modelContext.insert(cap)
                try? modelContext.save()
                customText = ""
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(appState.accentColor)
            }
        }
        .padding(.horizontal, 12)
    }

    private var tabRow: some View {
        HStack(spacing: 4) {
            ForEach(CaptionTab.allCases) { tab in
                let isSel = tab == captionTab
                Text(tab.rawValue.capitalized)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isSel ? appState.accentColor : Theme.text2(appState.colorMode, cs))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .overlay(
                        Rectangle()
                            .fill(isSel ? appState.accentColor : Color.clear)
                            .frame(height: 1.5)
                            .offset(y: 10)
                    )
                    .onTapGesture { captionTab = tab }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
    }

    private var captionList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filteredCaptions) { cap in
                    captionCard(cap)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 40)
        }
    }

    private func captionCard(_ cap: DumpCaption) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(cap.text)
                .font(.system(size: 14))
                .foregroundColor(cap.banned ? Theme.removeText : Theme.text(appState.colorMode, cs))
                .strikethrough(cap.banned)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 12) {
                if cap.banned {
                    Text("NEVER USE")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.removeText)
                        .cornerRadius(3)
                }
                Text(cap.style.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.0)
                    .foregroundColor(Theme.text3(appState.colorMode, cs))
                Spacer()
                actionButton("doc.on.doc") { UIPasteboard.general.string = cap.text }
                actionButton(cap.favorited ? "hand.thumbsup.fill" : "hand.thumbsup",
                             tint: cap.favorited ? appState.accentColor : nil) {
                    cap.favorited.toggle()
                    if cap.favorited { cap.banned = false }
                    try? modelContext.save()
                }
                actionButton(cap.banned ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                             tint: cap.banned ? Theme.removeText : nil) {
                    cap.banned.toggle()
                    if cap.banned { cap.favorited = false }
                    try? modelContext.save()
                }
                actionButton("trash") {
                    modelContext.delete(cap)
                    try? modelContext.save()
                }
            }
        }
        .padding(12)
        .background(cap.banned ? Theme.removeText.opacity(0.08) : Theme.bg2(appState.colorMode, cs))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func actionButton(_ symbol: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundColor(tint ?? Theme.text2(appState.colorMode, cs))
                .frame(width: 26, height: 26)
        }
    }
}
