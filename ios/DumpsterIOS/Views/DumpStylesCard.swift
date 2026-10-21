import SwiftUI

/// Settings card for Dump Styles. Port of DumpStylesSection in MainMenu.tsx.
/// Every edit / activate / delete persists locally and calls scheduleCloudSync().
struct DumpStylesCard: View {
    private let gold = Color(hex: "#C8A96E")
    /// Optional — when present, activating/deactivating a style also flashes the header status.
    var appState: AppState? = nil
    static let usedBy = "Used by Captions and the Valet"   // web: DUMP_STYLE_USED_BY (Auto-arrange is on-device here)

    @State private var styles = DumpStyle.load()
    @State private var activeId = DumpStyle.activeId()
    @State private var editId = ""          // editor stays closed until a style chip is tapped
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
                chip("None", on: activeId.isEmpty) { activate(""); editId = "" }
                ForEach(styles) { s in
                    chip(s.name.isEmpty ? "Untitled" : s.name, on: s.id == activeId, active: s.id == activeId) { activate(s.id); editId = (editId == s.id) ? "" : s.id }
                }
                chip("+ New style", on: false, dashed: true) { addStyle() }
            }

            Text(Self.usedBy)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.35))

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
        .onReceive(NotificationCenter.default.publisher(for: .dumpStylesChanged)) { _ in styles = DumpStyle.load() }
    }

    // MARK: - Actions (each one persists + schedules a cloud save)

    private func activate(_ id: String) {
        activeId = id
        UserDefaults.standard.set(id, forKey: DumpStyle.activeKey)
        confirmDelete = false
        scheduleCloudSync()
        // Confirmation toast (web: "<name> style on" / "Dump style off").
        let name = styles.first(where: { $0.id == id })?.name ?? ""
        let msg = id.isEmpty ? "Dump style off" : "\(name.isEmpty ? "Untitled" : name) style on"
        appState?.showStatus(msg)
        status = msg
        statusTask?.cancel()
        statusTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            status = ""
        }
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
                // Same caps as web's maxLength on the style editors.
                let cap = kp == \DumpStyle.rules ? AIProfileLimits.aiRulesMax : (kp == \DumpStyle.profile ? AIProfileLimits.tasteProfileMax : 80)
                styles[idx][keyPath: kp] = String(v.prefix(cap))
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

    private func chip(_ title: String, on: Bool, dashed: Bool = false, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                if active {
                    Text("ACTIVE")
                        .font(.system(size: 8, weight: .heavy)).tracking(1)
                        .foregroundColor(.black)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(gold))
                }
            }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(on ? .white : .white.opacity(0.6))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(on ? gold.opacity(0.18) : Color.black.opacity(0.3)))
                .overlay(Capsule().stroke(on ? gold : Color.white.opacity(0.15),
                                          style: StrokeStyle(lineWidth: 1, dash: dashed ? [3] : [])))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
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
