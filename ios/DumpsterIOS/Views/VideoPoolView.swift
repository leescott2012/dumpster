import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

/// Device-only Video Pool (mirror of web VideoPool). Videos are never uploaded or synced.
struct VideoPoolView: View {

    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var cs

    @Query(sort: \VideoItem.addedAt, order: .reverse) private var videos: [VideoItem]

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showFiles = false
    @State private var importing = false
    @State private var importError: String?
    @State private var openVideo: VideoItem?
    @State private var toDelete: VideoItem?

    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 10)]

    var body: some View {
        VStack(spacing: 12) {
            header
            if videos.isEmpty && !importing {
                emptyState
            } else {
                LazyVGrid(columns: cols, spacing: 10) {
                    ForEach(videos) { v in tile(v) }
                }
                .padding(.horizontal, 14)
            }
        }
        .task { await backfillTags() }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPicked(items) }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.movie], allowsMultipleSelection: true) { res in
            guard case .success(let urls) = res else { return }
            Task { await importFiles(urls) }
        }
        .sheet(item: $openVideo) { v in VideoSheet(video: v) }
        .confirmationDialog("Delete this video from your pool?", isPresented: Binding(
            get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let v = toDelete { VideoStore.deleteFiles(v); modelContext.delete(v); try? modelContext.save() }
                toDelete = nil
            }
            Button("Cancel", role: .cancel) { toDelete = nil }
        } message: { Text("The video file is removed from this device.") }
        .alert("Couldn't add video", isPresented: Binding(
            get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(importError ?? "") }
    }

    // MARK: Header / empty

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Videos").font(.system(size: 20, weight: .bold))
                    .foregroundColor(Theme.text(appState.colorMode, cs))
                Text("Videos stay on this device — never uploaded.").font(.system(size: 11))
                    .foregroundColor(Theme.text3(appState.colorMode, cs))
            }
            Spacer()
            if importing { ProgressView().tint(Theme.gold) }
            if !videos.isEmpty { addButtons }
        }
        .padding(.horizontal, 14)
    }

    private var addButtons: some View {
        HStack(spacing: 6) {
            PhotosPicker(selection: $pickerItems, matching: .videos) {
                Label("Add", systemImage: "plus").font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Theme.gold).foregroundColor(.black).clipShape(Capsule())
            }
            .accessibilityLabel("Add videos from Photos")
            Button { showFiles = true } label: {
                Image(systemName: "folder").font(.system(size: 13, weight: .semibold))
                    .padding(8).foregroundColor(Theme.gold)
                    .overlay(Circle().stroke(Theme.gold, lineWidth: 1))
            }
            .accessibilityLabel("Add videos from Files")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "play.rectangle").font(.system(size: 36))
            Text("Videos stay on this device").font(.system(size: 15, weight: .semibold))
            Text("Your videos are never uploaded.").font(.system(size: 12))
            HStack(spacing: 10) {
                PhotosPicker(selection: $pickerItems, matching: .videos) {
                    Text("Add Videos").font(.system(size: 14, weight: .bold))
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Theme.gold).foregroundColor(.black).clipShape(Capsule())
                }
                .accessibilityLabel("Add videos from Photos")
                Button("From Files") { showFiles = true }
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.gold)
                    .accessibilityLabel("Add videos from Files")
            }
        }
        .foregroundColor(Theme.text3(appState.colorMode, cs))
        .frame(maxWidth: .infinity).padding(.vertical, 50)
    }

    // MARK: Tile

    private func tile(_ v: VideoItem) -> some View {
        ZStack(alignment: .bottom) {
            VideoThumb(url: v.thumbURL)
                .frame(maxWidth: .infinity).aspectRatio(3.0/4.0, contentMode: .fit)
                .clipped()
            VStack(alignment: .leading, spacing: 4) {
                if !v.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(v.tags.prefix(3), id: \.self) { t in
                            Text(t).font(.system(size: 9, weight: .bold)).lineLimit(1)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.gold.opacity(0.9)).foregroundColor(.black).clipShape(Capsule())
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(6)
        }
        .overlay(alignment: .topLeading) {
            if v.isTrimmed {
                Text("TRIMMED").font(.system(size: 9, weight: .heavy))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.gold).foregroundColor(.black).clipShape(Capsule()).padding(6)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { toDelete = v } label: {
                Image(systemName: "trash").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                    .padding(7).background(Color.black.opacity(0.6)).clipShape(Circle())
            }
            .padding(4)
            .accessibilityLabel("Delete \(v.name)")
        }
        .overlay(alignment: .bottomTrailing) {
            Text(fmtTime(v.shownLength)).font(.system(size: 10, weight: .bold).monospacedDigit())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.black.opacity(0.7)).foregroundColor(.white).clipShape(Capsule()).padding(6)
                .offset(y: v.tags.isEmpty ? 0 : -22)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Theme.border2(appState.colorMode, cs), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { openVideo = v }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(v.name), \(fmtTime(v.shownLength))\(v.isTrimmed ? ", trimmed" : "")")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { openVideo = v }
    }

    // MARK: Import

    private func importPicked(_ items: [PhotosPickerItem]) async {
        importing = true
        defer { importing = false; pickerItems.removeAll() }
        for item in items {
            do {
                guard let m = try await item.loadTransferable(type: PickedMovie.self) else { continue }
                await add(m.url, name: "Video \(videos.count + 1)")
            } catch { importError = error.localizedDescription }
        }
    }

    private func importFiles(_ urls: [URL]) async {
        importing = true
        defer { importing = false }
        for u in urls {
            if let dest = VideoStore.importFile(at: u) {
                await add(dest, name: u.deletingPathExtension().lastPathComponent)
            } else { importError = "Couldn't copy \(u.lastPathComponent)." }
        }
    }

    /// Videos added before auto-labels existed: label each once, on-device only (free — never spends credits).
    private func backfillTags() async {
        for v in videos where v.tags.isEmpty {
            let t = await VideoStore.autoTags(id: v.id, thumbPath: v.thumbPath, thumbURL: v.thumbURL, allowCloud: false)
            if !t.isEmpty { v.tags = t }
        }
        try? modelContext.save()
    }

    private func add(_ fileURL: URL, name: String) async {
        let item = await VideoStore.makeItem(fileURL: fileURL, name: name)
        modelContext.insert(item)
        try? modelContext.save()
    }
}

/// Grid thumbnail: loads the (already ≤480px) JPEG via ImageIO downsample off the main thread.
struct VideoThumb: View {
    let url: URL?
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            Color(hex: "#181818")
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "play.rectangle").foregroundColor(.gray)
            }
        }
        .task(id: url) {
            guard let url else { return }
            image = await Task.detached(priority: .utility) {
                let opts = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceThumbnailMaxPixelSize: 480,
                            kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary
                guard let s = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(s, 0, opts) else { return nil as UIImage? }
                return UIImage(cgImage: cg)
            }.value
        }
        .accessibilityHidden(true)
    }
}
