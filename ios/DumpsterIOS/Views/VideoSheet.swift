import SwiftUI
import SwiftData
import AVKit

/// Play + non-destructive trim for a device-only pool video (mirror of web VideoSheet).
struct VideoSheet: View {

    let video: VideoItem

    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var player = AVPlayer()
    @State private var observer: Any?
    @State private var start: Double = 0
    @State private var end: Double = 0
    @State private var progress: Double?
    @State private var copyURL: URL?
    @State private var errorText: String?
    @State private var newTag = ""
    @State private var tags: [String] = []

    private let minGap = 0.5
    private let presetTags = ["Outfit", "Travel", "Car", "Other"]
    private var dur: Double { video.duration }
    private var exporting: Bool { progress != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(video.name).font(.system(size: 16, weight: .bold)).lineLimit(1)
                        Text("Stays on this device — never uploaded").font(.system(size: 11)).foregroundColor(.gray)
                    }
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark").padding(8) }
                        .accessibilityLabel("Close")
                }

                VideoPlayer(player: player)
                    .frame(height: 320).clipShape(RoundedRectangle(cornerRadius: 10))

                if dur > 0 {
                    RangeSlider(start: $start, end: $end, total: dur, minGap: minGap, disabled: exporting)
                    HStack {
                        Text("In \(fmtTime(start))")
                        Spacer()
                        Text(fmtTime(end - start)).fontWeight(.bold).foregroundColor(.white)
                            .accessibilityLabel("Trimmed length \(fmtTime(end - start))")
                        Spacer()
                        Text("Out \(fmtTime(end))")
                    }
                    .font(.system(size: 11).monospacedDigit()).foregroundColor(.gray)
                } else {
                    Text("Loading length…").font(.system(size: 12)).foregroundColor(.gray)
                }

                HStack(spacing: 8) {
                    Button("Reset") { start = 0; end = dur; seek(0) }
                        .disabled(exporting || dur == 0)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .overlay(Capsule().stroke(Color.gray.opacity(0.5)))
                        .accessibilityLabel("Reset trim")
                    Button { Task { await saveCopy() } } label: {
                        HStack(spacing: 6) {
                            if exporting { ProgressView().tint(.black) } else { Image(systemName: "scissors") }
                            Text(exporting ? "Exporting \(Int((progress ?? 0) * 100))%" : "Save trimmed copy")
                        }
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Theme.gold).foregroundColor(.black).clipShape(Capsule())
                    }
                    .disabled(exporting || dur == 0)
                    if let copyURL {
                        ShareLink(item: copyURL) {
                            Label("Share / Save", systemImage: "square.and.arrow.up").font(.system(size: 13))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .overlay(Capsule().stroke(Theme.gold))
                        }
                        .accessibilityLabel("Share or save trimmed copy")
                    }
                }
                if let p = progress { ProgressView(value: p).tint(Theme.gold) }
                if let errorText {
                    Text("\(errorText) Your original is untouched.").font(.system(size: 12)).foregroundColor(.red)
                }

                tagEditor
            }
            .foregroundColor(.white)
            .padding(20)
        }
        .background(Color(hex: "#0E0E0E").ignoresSafeArea())
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .onAppear(perform: setup)
        .onDisappear(perform: teardown)
        // Auto-save trim (debounced; cancels on each change). Full range = untrimmed.
        .task(id: [start, end]) {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, dur > 0 else { return }
            if start <= 0.05 && end >= dur - 0.05 { video.trimStart = nil; video.trimEnd = nil }
            else { video.trimStart = start; video.trimEnd = end }
            try? modelContext.save()
        }
    }

    // MARK: Tags

    private var tagEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags").font(.system(size: 12, weight: .bold)).foregroundColor(.gray)
            let all = presetTags + tags.filter { !presetTags.contains($0) }
            FlowChips(items: all, selected: Set(tags)) { t in
                if let i = tags.firstIndex(of: t) { tags.remove(at: i) } else { tags.append(t) }
                video.tags = tags; try? modelContext.save()
            }
            HStack {
                TextField("Add tag", text: $newTag).textFieldStyle(.roundedBorder)
                    .submitLabel(.done).onSubmit(addTag)
                Button("Add", action: addTag).disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addTag() {
        let t = newTag.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !tags.contains(t) else { newTag = ""; return }
        tags.append(t); video.tags = tags; newTag = ""; try? modelContext.save()
    }

    // MARK: Player

    private func setup() {
        let r = video.range
        start = r.start; end = r.end; tags = video.tags
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.replaceCurrentItem(with: AVPlayerItem(url: video.fileURL))
        seek(start)
        if !reduceMotion { player.play() }   // no autoplay under Reduce Motion
        // Loop only [start, end].
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { t in
            if t.seconds >= end || t.seconds < start - 0.25 {
                seek(start)
                if player.timeControlStatus == .paused && !reduceMotion { player.play() }
            }
        }
    }

    private func teardown() {
        if let observer { player.removeTimeObserver(observer) }
        observer = nil
        player.pause()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func seek(_ t: Double) {
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: Export

    private func saveCopy() async {
        errorText = nil; copyURL = nil; progress = 0
        player.pause()
        do {
            let res = try await VideoStore.exportTrimmed(source: video.fileURL, start: start, end: end) { p in
                Task { @MainActor in progress = p }
            }
            let item = await VideoStore.makeItem(fileURL: res.url, name: "\(video.name) (trimmed)", knownDuration: res.duration)
            item.tags = video.tags
            modelContext.insert(item)
            try? modelContext.save()
            copyURL = res.url
        } catch {
            errorText = "Couldn't make a trimmed copy — \(error.localizedDescription)."
        }
        progress = nil
        if !reduceMotion { player.play() }
    }
}

/// Wrapping chip row.
private struct FlowChips: View {
    let items: [String]
    let selected: Set<String>
    let tap: (String) -> Void
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { t in
                Button { tap(t) } label: {
                    Text(t).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        .padding(.horizontal, 10).padding(.vertical, 6).frame(maxWidth: .infinity)
                        .background(selected.contains(t) ? Theme.gold : Color.white.opacity(0.08))
                        .foregroundColor(selected.contains(t) ? .black : .white).clipShape(Capsule())
                }
                .accessibilityLabel(t)
                .accessibilityAddTraits(selected.contains(t) ? .isSelected : [])
            }
        }
    }
}

/// Two-handle in/out slider. Each handle is an adjustable accessibility element (1s steps).
struct RangeSlider: View {
    @Binding var start: Double
    @Binding var end: Double
    let total: Double
    let minGap: Double
    var disabled = false

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width - 24)
            let x0 = 12 + CGFloat(start / total) * w
            let x1 = 12 + CGFloat(end / total) * w
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12)).frame(height: 6).padding(.horizontal, 12)
                Capsule().fill(Theme.gold).frame(width: max(0, x1 - x0), height: 6).offset(x: x0)
                handle(x: x0, label: "Trim start", value: start)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("rs")).onChanged { g in
                        let t = Double((g.location.x - 12) / w) * total
                        start = min(max(0, t), end - minGap)
                    })
                    .accessibilityValue("\(fmtTime(start))")
                    .accessibilityAdjustableAction { d in
                        start = d == .increment ? min(start + 1, end - minGap) : max(start - 1, 0)
                    }
                handle(x: x1, label: "Trim end", value: end)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("rs")).onChanged { g in
                        let t = Double((g.location.x - 12) / w) * total
                        end = max(min(total, t), start + minGap)
                    })
                    .accessibilityValue("\(fmtTime(end))")
                    .accessibilityAdjustableAction { d in
                        end = d == .increment ? min(end + 1, total) : max(end - 1, start + minGap)
                    }
            }
            .coordinateSpace(name: "rs")
        }
        .frame(height: 32)
        .opacity(disabled ? 0.5 : 1).allowsHitTesting(!disabled)
    }

    private func handle(x: CGFloat, label: String, value: Double) -> some View {
        RoundedRectangle(cornerRadius: 4).fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.gold, lineWidth: 2))
            .frame(width: 18, height: 30)
            .contentShape(Rectangle().inset(by: -8))
            .offset(x: x - 9)
            .accessibilityElement().accessibilityLabel(label)
    }
}
