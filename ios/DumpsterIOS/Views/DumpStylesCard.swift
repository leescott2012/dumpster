import SwiftUI

/// Settings card for Dump Styles. Port of DumpStylesSection in MainMenu.tsx.
/// Every edit / activate / delete persists locally and calls scheduleCloudSync().
struct DumpStylesCard: View {
    private let gold = Color(hex: "#C8A96E")

    @State private var styles = DumpStyle.load()
    @State private var activeId = DumpStyle.activeId()
    @State private var editId = DumpStyle.activeId().isEmpty ? (DumpStyle.load().first?.id ?? "") : DumpStyle.activeId()
    @State private var confirmDelete = false
    @State private var status = ""          // "", "Saving…", "Saved"
    @State private var statusTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Saved recipes for how the AI builds your dumps. The active one is used on every AI suggestion.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
                    .lineSpacing(3)
                Spacer(minLength: 8)
                Text(status)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(gold)
            }

            FlowLayout(spacing: 6) {
                chip("None", on: activeId.isEmpty) { activate("") }
                ForEach(styles) { s in
                    chip((s.name.isEmpty ? "Untitled" : s.name) + (s.id == activeId ? " · Active" : ""),
                         on: s.id == activeId) { activate(s.id) }
                }
                chip("+ New style", on: false, dashed: true) { addStyle() }
            }

            if let idx = styles.firstIndex(where: { $0.id == editId }) {
                field("Name", text: binding(idx, \.name), height: 36)
                field("Recipe (structure, sequencing, poses, mix)", text: binding(idx, \.profile), height: 90)
                field("Rules for this style", text: binding(idx, \.rules), height: 70)
                Button(confirmDelete ? "Tap again to delete" : "Delete style") { remove() }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.red.opacity(0.8))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(gold.opacity(0.18), lineWidth: 1))
    }

    // MARK: - Actions (each one persists + schedules a cloud save)

    private func activate(_ id: String) {
        activeId = id
        UserDefaults.standard.set(id, forKey: DumpStyle.activeKey)
        if !id.isEmpty { editId = id }
        confirmDelete = false
        scheduleCloudSync()
    }

    private func addStyle() {
        let s = DumpStyle.new()
        styles.append(s)
        editId = s.id
        confirmDelete = false
        persist()
    }

    private func remove() {
        guard confirmDelete else { confirmDelete = true; return }
        styles.removeAll { $0.id == editId }
        if activeId == editId { activate("") }
        editId = ""
        confirmDelete = false
        persist()
    }

    private func binding(_ idx: Int, _ kp: WritableKeyPath<DumpStyle, String>) -> Binding<String> {
        Binding(
            get: { idx < styles.count ? styles[idx][keyPath: kp] : "" },
            set: { v in
                guard idx < styles.count else { return }
                styles[idx][keyPath: kp] = v
                styles[idx].updatedAt = DumpStyle.nowISO()
                persist()
            }
        )
    }

    private func persist() {
        DumpStyle.save(styles)
        scheduleCloudSync()
        status = "Saving…"
        statusTask?.cancel()
        statusTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            status = "Saved"
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            status = ""
        }
    }

    private func scheduleCloudSync() {
        guard let userId = AuthManager.shared.userId, let jwt = AuthManager.shared.jwt else { return }
        AIProfileSync.shared.scheduleSave(userId: userId, jwt: jwt)
    }

    // MARK: - Pieces

    private func chip(_ title: String, on: Bool, dashed: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(on ? .white : .white.opacity(0.6))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(on ? gold.opacity(0.18) : Color.black.opacity(0.3)))
                .overlay(Capsule().stroke(on ? gold : Color.white.opacity(0.15),
                                          style: StrokeStyle(lineWidth: 1, dash: dashed ? [3] : [])))
        }
        .buttonStyle(.plain)
    }

    private func field(_ placeholder: String, text: Binding<String>, height: CGFloat) -> some View {
        TextEditor(text: text)
            .font(.system(size: 13))
            .foregroundColor(.white)
            .scrollContentBackground(.hidden)
            .frame(height: height)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.3)))
            .overlay(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder).font(.system(size: 13)).foregroundColor(.white.opacity(0.25))
                        .padding(.horizontal, 13).padding(.vertical, 16).allowsHitTesting(false)
                }
            }
    }
}
