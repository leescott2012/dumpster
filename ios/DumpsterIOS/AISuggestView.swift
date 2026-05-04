import SwiftUI
import SwiftData
import PhotosUI
import ImageIO

// MARK: - AI Suggest Button (Floating Overlay)

struct AIButton: View {
    @Binding var isPresented: Bool
    private let gold = Color(red: 200/255, green: 169/255, blue: 110/255)

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    isPresented = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                        Text("AI SUGGEST")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(2)
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 13)
                    .background(gold)
                    .clipShape(Capsule())
                    .shadow(color: gold.opacity(0.4), radius: 12, x: 0, y: 4)
                }
                .padding(.trailing, 24)
                .padding(.bottom, 48)
            }
        }
    }
}

// MARK: - Main AI Suggest Flow

struct AISuggestView: View {
    @Binding var isPresented: Bool
    @ObservedObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query private var existingDumps: [PhotoDump]

    @State private var phase: Phase = .picker
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isAnalyzing = false
    @State private var clusters: [PhotoCluster] = []
    @State private var selectedClusters: Set<Int> = []
    @State private var progress: Double = 0.0
    @State private var statusMessage: String = ""
    @State private var isCreating = false

    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    private let gold = Color(red: 200/255, green: 169/255, blue: 110/255)
    private let llmService = LLMService.shared

    enum Phase { case picker, results }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text(phase == .picker ? "AI BUILDER" : "SUGGESTED DUMPS")
                        .font(.system(size: 12, weight: .black))
                        .tracking(3)
                        .foregroundColor(gold)

                    Spacer()

                    // Show active provider indicator
                    if let provider = llmService.preferredProvider() {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 5, height: 5)
                            Text(provider.displayName)
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1)
                                .foregroundColor(gold.opacity(0.5))
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)
                .padding(.bottom, 20)

                switch phase {
                case .picker:
                    pickerPhase
                case .results:
                    resultsPhase
                }
            }

            // Close button
            Button {
                haptic.impactOccurred()
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
            .padding(.trailing, 24)
            .padding(.top, 50)

            // Create button (results phase)
            if phase == .results && !clusters.isEmpty {
                VStack {
                    Spacer()
                    Button {
                        haptic.impactOccurred()
                        createDumps()
                    } label: {
                        HStack(spacing: 8) {
                            if isCreating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                    .scaleEffect(0.7)
                            }
                            Text(isCreating
                                 ? "CREATING..."
                                 : "CREATE \(selectedClusters.count) DUMP\(selectedClusters.count == 1 ? "" : "S")")
                                .font(.system(size: 13, weight: .bold))
                                .tracking(3)
                                .foregroundColor(.black)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(selectedClusters.isEmpty || isCreating ? Color.gray : gold)
                        .cornerRadius(14)
                    }
                    .disabled(selectedClusters.isEmpty || isCreating)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Picker Phase

    private var pickerPhase: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(gold)
                Text("AI DUMP BUILDER")
                    .font(.system(size: 18, weight: .black))
                    .tracking(4)
                    .foregroundColor(.white)
                Text("Pick your photos and Vision AI will\ngroup them into perfect dumps.")
                    .font(.system(size: 15))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.4))
                    .lineSpacing(5)
            }

            if !isAnalyzing {
                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: 100,
                    matching: .images
                ) {
                    Text("SELECT PHOTOS")
                        .font(.system(size: 13, weight: .bold))
                        .tracking(3)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(gold)
                        .cornerRadius(14)
                }
                .padding(.horizontal, 32)
                .onChange(of: selectedItems) { oldItems, newItems in
                    guard !newItems.isEmpty else { return }
                    haptic.impactOccurred()
                    isAnalyzing = true
                    appState.isAnalyzing = true
                    appState.showStatus("Analyzing photos...", duration: 60)
                    loadAndAnalyze(items: newItems)
                }
            } else {
                VStack(spacing: 16) {
                    ProgressView(value: progress)
                        .tint(gold)
                        .frame(width: 200)
                    Text(statusMessage.isEmpty ? "Analyzing \(Int(progress * 100))%..." : statusMessage)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.4))
                }
            }

            Spacer()
        }
    }

    // MARK: - Results Phase

    private var resultsPhase: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Tap to select which dumps to create")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)

                ForEach(Array(clusters.enumerated()), id: \.offset) { i, cluster in
                    ClusterRow(cluster: cluster, selected: selectedClusters.contains(i)) {
                        haptic.impactOccurred(intensity: 0.6)
                        if selectedClusters.contains(i) {
                            selectedClusters.remove(i)
                        } else {
                            selectedClusters.insert(i)
                        }
                    }
                }

                Color.clear.frame(height: 100)
            }
        }
    }

    // MARK: - Load & Analyze

    private func loadAndAnalyze(items: [PhotosPickerItem]) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dumpster_ai", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let lock = NSLock()
        var loaded: [(UIImage, URL)] = []
        let total = Double(items.count)
        var completed = 0.0

        DispatchQueue.global(qos: .userInitiated).async {
            let group = DispatchGroup()
            let semaphore = DispatchSemaphore(value: 3)

            for item in items {
                semaphore.wait()
                group.enter()

                item.loadTransferable(type: Data.self) { result in
                    defer {
                        group.leave()
                        semaphore.signal()
                    }

                    guard case .success(let data) = result, let data,
                          let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                        DispatchQueue.main.async {
                            completed += 1
                            self.progress = completed / total
                        }
                        return
                    }

                    let options: [CFString: Any] = [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 512
                    ]

                    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                        DispatchQueue.main.async {
                            completed += 1
                            self.progress = completed / total
                        }
                        return
                    }

                    let thumbnail = UIImage(cgImage: cgImage)
                    let filename = "\(UUID().uuidString).jpg"
                    let url = tempDir.appendingPathComponent(filename)

                    if let thumbData = thumbnail.jpegData(compressionQuality: 0.7) {
                        try? thumbData.write(to: url)
                    }

                    lock.lock()
                    loaded.append((thumbnail, url))
                    lock.unlock()

                    DispatchQueue.main.async {
                        completed += 1
                        self.progress = completed / total
                    }
                }
            }

            group.notify(queue: .main) {
                self.statusMessage = "Clustering photos..."

                lock.lock()
                let safeLoaded = loaded
                lock.unlock()

                PhotoAnalyzer.analyze(images: safeLoaded) { result in
                    self.clusters = result
                    self.selectedClusters = Set(result.indices)
                    self.isAnalyzing = false
                    self.appState.isAnalyzing = false
                    self.appState.showStatus("Found \(result.count) dumps", duration: 3)
                    self.statusMessage = ""
                    withAnimation { self.phase = .results }

                    // Trigger caption generation using LLMService
                    self.generateCaptionsForClusters(result)
                }
            }
        }
    }

    // MARK: - Caption Generation (Now uses LLMService)

    private func generateCaptionsForClusters(_ clusters: [PhotoCluster]) {
        let requests = clusters.map { cluster in
            LLMService.CaptionRequest(
                dumpTitle: cluster.title,
                category: cluster.category,
                labels: cluster.allLabels,
                photoCount: cluster.photos.count
            )
        }

        if llmService.hasAnyAPIKey {
            // Use the best available LLM provider
            let providerName = llmService.preferredProvider()?.displayName ?? "AI"
            appState.showStatus("Generating captions via \(providerName)...", duration: 30)
            Task {
                do {
                    let results = try await llmService.generateCaptions(for: requests)
                    await MainActor.run {
                        appState.captionResults = results
                        appState.showStatus("Captions ready", duration: 3)
                    }
                } catch {
                    print("[AISuggest] Caption generation failed: \(error)")
                    await MainActor.run {
                        let fallbacks = requests.map {
                            LLMService.fallbackCaptions(for: $0.category, title: $0.dumpTitle)
                        }
                        appState.captionResults = fallbacks
                        appState.showStatus("Using local captions", duration: 3)
                    }
                }
            }
        } else {
            // No API key — use local fallback captions
            let fallbacks = requests.map {
                LLMService.fallbackCaptions(for: $0.category, title: $0.dumpTitle)
            }
            appState.captionResults = fallbacks
        }
    }

    // MARK: - Create Dumps (Native SwiftData — Phase 6)

    private func createDumps() {
        isCreating = true
        appState.showStatus("Creating dumps...", duration: 10)

        let selectedGroups = clusters.enumerated()
            .filter { selectedClusters.contains($0.offset) }
            .map { $0.element }

        var nextNum = (existingDumps.map { $0.num }.max() ?? 0) + 1

        for cluster in selectedGroups {
            // 1. Save each AnalyzedPhoto's UIImage to disk + insert DumpPhoto.
            var photoIDs: [String] = []
            for p in cluster.photos {
                let relPath = PhotoStorageManager.shared.saveImage(
                    p.image,
                    filename: p.filename
                )
                let dp = DumpPhoto(
                    localPath: relPath,
                    filename: p.filename,
                    category: p.category,
                    labels: p.labels,
                    starred: false,
                    isHuji: FormulaEngine.detectHuji(filename: p.filename)
                )
                modelContext.insert(dp)
                photoIDs.append(dp.id)
                if photoIDs.count >= 20 { break }
            }

            // 2. Create the PhotoDump record.
            let vibe: String?
            // Resolve the photos we just created back into DumpPhoto for vibe check.
            // (The AnalyzedPhoto.category is sufficient for the warm/cool ratio.)
            let stub = cluster.photos.map { p -> DumpPhoto in
                DumpPhoto(localPath: "", filename: p.filename, category: p.category, labels: p.labels)
            }
            vibe = FormulaEngine.checkColorTemp(stub) ? nil : "mismatch"

            let dump = PhotoDump(
                num: nextNum,
                title: cluster.title,
                photoIDs: photoIDs,
                vibeBadge: vibe,
                liked: false,
                titleApproved: nil
            )
            modelContext.insert(dump)
            nextNum += 1

            // 3. Save associated captions if we generated any.
            if let cr = appState.captionResults.first(where: { $0.dumpTitle == cluster.title }) {
                for line in cr.captions {
                    let cap = DumpCaption(text: line, style: "ai", dumpId: dump.id)
                    modelContext.insert(cap)
                }
            }
        }

        do {
            try modelContext.save()
            isCreating = false
            appState.showStatus("Dumps created!", duration: 3)
            appState.dumpCount = existingDumps.count
            isPresented = false
        } catch {
            print("[AISuggest] SwiftData save error: \(error)")
            isCreating = false
            appState.showStatus("Error creating dumps", duration: 3)
        }
    }
}

// MARK: - Cluster Row

struct ClusterRow: View {
    let cluster: PhotoCluster
    let selected: Bool
    let onTap: () -> Void

    private let gold = Color(red: 200/255, green: 169/255, blue: 110/255)

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(cluster.title)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                        Text("\(cluster.photos.count) photos \u{00B7} \(cluster.category)")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                            .tracking(1)
                    }
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundColor(selected ? gold : .white.opacity(0.2))
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(cluster.photos.prefix(8).enumerated()), id: \.offset) { _, photo in
                            Image(uiImage: photo.image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 72, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                if !cluster.allLabels.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(cluster.allLabels.prefix(5).enumerated()), id: \.offset) { _, label in
                                Text(label)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.white.opacity(0.4))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.06))
                                    .cornerRadius(6)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(selected
                          ? Color(red: 200/255, green: 169/255, blue: 110/255).opacity(0.08)
                          : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(selected ? gold.opacity(0.4) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.vertical, 4)
    }
}
