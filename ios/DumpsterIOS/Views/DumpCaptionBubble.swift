import SwiftUI
import SwiftData

/// Caption bubble on a dump card (native twin of the web DumpStrip caption bubble):
/// "<VIBE> · n/3 CAPTIONS" header, copy, prev/next, tap the text to edit in place.
/// Reads the dump's saved captions (DumpCaption rows with dumpId == dump.id, oldest first);
/// edits are written straight back to the caption row.
struct DumpCaptionBubble: View {

    let dump: PhotoDump

    @Query private var captions: [DumpCaption]

    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var cs
    @State private var idx = 0
    @State private var copied = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    init(dump: PhotoDump) {
        self.dump = dump
        let id: String? = dump.id
        _captions = Query(
            filter: #Predicate<DumpCaption> { $0.dumpId == id && !$0.deleted && !$0.banned },
            sort: \DumpCaption.createdAt
        )
    }

    var body: some View {
        if !captions.isEmpty {
            let total = captions.count
            let i = min(idx, total - 1)
            let current = captions[i]

            HStack(alignment: .top, spacing: 13) {
                Rectangle().fill(appState.accentColor).frame(width: 3)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Text(header(i, total))
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.2)
                            .foregroundColor(appState.accentColor)
                        Spacer(minLength: 0)
                        iconButton(copied ? "checkmark" : "doc.on.doc", label: "Copy caption",
                                   tint: copied ? .green : Theme.text2(appState.colorMode, cs)) {
                            UIPasteboard.general.string = current.text
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { copied = false }
                        }
                        if total > 1 {
                            iconButton("chevron.left", label: "Previous caption") { step(-1, total) }
                            iconButton("chevron.right", label: "Next caption") { step(1, total) }
                        }
                    }

                    if editing {
                        TextField("Caption", text: $draft, axis: .vertical)
                            .font(.system(size: 14))
                            .foregroundColor(Theme.text(appState.colorMode, cs))
                            .focused($focused)
                            .padding(8)
                            .background(Theme.bg2(appState.colorMode, cs))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        HStack(spacing: 16) {
                            Button("Save") { commit(current) }
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(appState.accentColor)
                            Button("Cancel") { editing = false }
                                .font(.system(size: 12))
                                .foregroundColor(Theme.text2(appState.colorMode, cs))
                        }
                    } else {
                        Text(current.text)
                            .font(.system(size: 14).italic())
                            .foregroundColor(Theme.text2(appState.colorMode, cs))
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("tap to edit")
                            .font(.system(size: 10))
                            .tracking(0.6)
                            .foregroundColor(Theme.text3(appState.colorMode, cs))
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !editing else { return }
                draft = current.text
                editing = true
                focused = true
            }
        }
    }

    private func header(_ i: Int, _ total: Int) -> String {
        let v = (dump.vibe ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return ((v.isEmpty ? "" : v + " · ") + "\(i + 1)/\(total) captions").uppercased()
    }

    private func step(_ d: Int, _ total: Int) {
        editing = false
        idx = (min(idx, total - 1) + d + total) % total
    }

    private func commit(_ cap: DumpCaption) {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty && t != cap.text {
            cap.text = t
            try? modelContext.save()
        }
        editing = false
    }

    private func iconButton(_ name: String, label: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(tint ?? Theme.text2(appState.colorMode, cs))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
