import SwiftUI
import SwiftData
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
    @Query private var allPhotos: [DumpPhoto]
    @Query(sort: \AITasteExample.createdAt, order: .reverse) private var tasteExamples: [AITasteExample]

    @State private var phase: Phase = .picker
    @State private var isAnalyzing = false
    @State private var clusters: [PhotoCluster] = []
    @State private var selectedClusters: Set<Int> = []
    @State private var progress: Double = 0.0
    @State private var statusMessage: String = ""
    @State private var isCreating = false
    @State private var maxPhotosPerDump: Int = 10
    @State private var requestedDumpCount: Int = 3
    // Maps AnalyzedPhoto.filename → existing DumpPhoto.id (pool source)
    @State private var poolPhotoMap: [String: String] = [:]

    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    private let gold = Color(red: 200/255, green: 169/255, blue: 110/255)
    private let llmService = LLMService.shared

    enum Phase { case picker, results }

    /// Pool photos = photos not assigned to any dump.
    private var availablePhotos: [DumpPhoto] {
        let usedIDs = Set(existingDumps.flatMap { $0.photoIDs })
        return allPhotos.filter { !usedIDs.contains($0.id) }
    }

    /// Upper bound for the stepper (pool size, capped at 20).
    private var stepperMax: Int {
        min(20, availablePhotos.count)
    }

    private var dumpCountMax: Int {
        3
    }

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

    /// Kick off full-pool analysis automatically — no user picking.
    private func startAutoAnalyze() {
        guard !availablePhotos.isEmpty else { return }
        isAnalyzing = true
        appState.isAnalyzing = true
        appState.showStatus("Analyzing photos...", duration: 60)
        loadAndAnalyzeFromPool(photos: availablePhotos)
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
                Text("Vision AI will analyze your pool and\nbuild dumps automatically.")
                    .font(.system(size: 15))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.4))
                    .lineSpacing(5)
            }

            if !llmService.hasAnyAPIKey {
                VStack(spacing: 10) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 22, weight: .light))
                        .foregroundColor(gold.opacity(0.6))
                    Text("No API Key Configured")
                        .font(.system(size: 13, weight: .bold))
                        .tracking(1)
                        .foregroundColor(.white.opacity(0.5))
                    Text("AI will use local logic to cluster your photos.\nAdd an API key in Settings for smarter results.")
                        .font(.system(size: 12))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white.opacity(0.3))
                        .lineSpacing(4)
                    Button("Add API Key") {
                        isPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            appState.showSettings = true
                        }
                    }
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(gold)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .overlay(Capsule().strokeBorder(gold.opacity(0.5), lineWidth: 1))
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 8)
            }

            if !isAnalyzing {
                HStack(spacing: 24) {
                    // Number of dumps stepper
                    VStack(spacing: 8) {
                        Text("DUMPS")
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(2)
                            .foregroundColor(.white.opacity(0.35))

                        HStack(spacing: 12) {
                            Button {
                                if requestedDumpCount > 1 { requestedDumpCount -= 1 }
                            } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(requestedDumpCount > 1 ? .white : .white.opacity(0.2))
                                    .frame(width: 36, height: 36)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(Circle())
                            }
                            .disabled(requestedDumpCount <= 1)

                            Text("\(requestedDumpCount)")
                                .font(.system(size: 32, weight: .bold, design: .monospaced))
                                .foregroundColor(gold)
                                .frame(width: 44)

                            Button {
                                if requestedDumpCount < dumpCountMax { requestedDumpCount += 1 }
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(requestedDumpCount < dumpCountMax ? .white : .white.opacity(0.2))
                                    .frame(width: 36, height: 36)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(Circle())
                            }
                            .disabled(requestedDumpCount >= dumpCountMax)
                        }

                        Text("max 3")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.2))
                    }

                    // Divider
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 1, height: 80)

                    // Photos per dump stepper
                    VStack(spacing: 8) {
                        Text("PHOTOS EACH")
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(2)
                            .foregroundColor(.white.opacity(0.35))

                        HStack(spacing: 12) {
                            Button {
                                if maxPhotosPerDump > 3 { maxPhotosPerDump -= 1 }
                            } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(maxPhotosPerDump > 3 ? .white : .white.opacity(0.2))
                                    .frame(width: 36, height: 36)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(Circle())
                            }
                            .disabled(maxPhotosPerDump <= 3)

                            Text("\(maxPhotosPerDump)")
                                .font(.system(size: 32, weight: .bold, design: .monospaced))
                                .foregroundColor(gold)
                                .frame(width: 44)

                            Button {
                                if maxPhotosPerDump < 20 { maxPhotosPerDump += 1 }
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(maxPhotosPerDump < 20 ? .white : .white.opacity(0.2))
                                    .frame(width: 36, height: 36)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(Circle())
                            }
                            .disabled(maxPhotosPerDump >= 20)
                        }

                        Text("max 20")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.2))
                    }
                }
                .padding(.horizontal, 32)

                // Pool size hint
                Text("\(availablePhotos.count) photo\(availablePhotos.count == 1 ? "" : "s") in pool")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.25))
                    .padding(.top, 4)

                if availablePhotos.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 28, weight: .light))
                            .foregroundColor(.white.opacity(0.2))
                        Text("No photos in pool")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white.opacity(0.3))
                        Text("Add photos to your pool first,\nthen use AI Builder to organize them.")
                            .font(.system(size: 12))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white.opacity(0.2))
                            .lineSpacing(4)
                    }
                    .padding(.horizontal, 32)
                } else {
                    Button {
                        haptic.impactOccurred()
                        startAutoAnalyze()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 15, weight: .semibold))
                            Text("AUTO-GENERATE \(availablePhotos.count) PHOTO\(availablePhotos.count == 1 ? "" : "S")")
                                .font(.system(size: 13, weight: .bold))
                                .tracking(3)
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(gold)
                        .cornerRadius(14)
                    }
                    .padding(.horizontal, 32)
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

    // MARK: - Load & Analyze from Pool

    private func loadAndAnalyzeFromPool(photos: [DumpPhoto]) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dumpster_ai", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let lock = NSLock()
        var loaded: [(UIImage, URL)] = []
        var map: [String: String] = [:]   // filename → DumpPhoto.id
        let total = Double(photos.count)
        var completed = 0.0

        DispatchQueue.global(qos: .userInitiated).async {
            for photo in photos {
                guard let original = PhotoStorageManager.shared.loadImage(relativePath: photo.localPath) else {
                    DispatchQueue.main.async {
                        completed += 1
                        self.progress = completed / total
                    }
                    continue
                }

                // Downsample to 512px for Vision analysis
                let thumbnail: UIImage
                let maxDim: CGFloat = 512
                let scale = min(maxDim / original.size.width, maxDim / original.size.height, 1.0)
                if scale < 1.0 {
                    let newSize = CGSize(width: original.size.width * scale, height: original.size.height * scale)
                    let renderer = UIGraphicsImageRenderer(size: newSize)
                    thumbnail = renderer.image { _ in original.draw(in: CGRect(origin: .zero, size: newSize)) }
                } else {
                    thumbnail = original
                }

                let filename = photo.id + ".jpg"
                let url = tempDir.appendingPathComponent(filename)
                if let data = thumbnail.jpegData(compressionQuality: 0.7) {
                    try? data.write(to: url)
                }

                lock.lock()
                loaded.append((thumbnail, url))
                map[filename] = photo.id
                lock.unlock()

                DispatchQueue.main.async {
                    completed += 1
                    self.progress = completed / total
                }
            }

            DispatchQueue.main.async {
                self.statusMessage = "Clustering photos..."
            }

            lock.lock()
            let safeLoaded = loaded
            let safeMap = map
            lock.unlock()

            PhotoAnalyzer.analyze(images: safeLoaded, limit: requestedDumpCount) { result in
                Task { @MainActor in
                    self.poolPhotoMap = safeMap
                    self.clusters = result
                    self.selectedClusters = Set(result.indices)
                    self.isAnalyzing = false
                    self.appState.isAnalyzing = false
                    self.appState.showStatus("Found \(result.count) dumps", duration: 3)
                    self.statusMessage = ""
                    withAnimation { self.phase = .results }
                    self.generateCaptionsForClusters(result)
                }
            }
        }
    }

    // MARK: - Caption Generation

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
            let providerName = llmService.preferredProvider()?.displayName ?? "AI"
            appState.showStatus("Generating captions via \(providerName)...", duration: 30)
            let tasteBlock = AITasteExample.promptBlock(from: Array(tasteExamples.prefix(10)))
            Task {
                do {
                    let results = try await llmService.generateCaptions(for: requests, tasteBlock: tasteBlock)
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
            let fallbacks = requests.map {
                LLMService.fallbackCaptions(for: $0.category, title: $0.dumpTitle)
            }
            appState.captionResults = fallbacks
        }
    }

    // MARK: - Create Dumps

    private func createDumps() {
        isCreating = true
        appState.showStatus("Creating dumps...", duration: 10)

        let selectedGroups = clusters.enumerated()
            .filter { selectedClusters.contains($0.offset) }
            .map { $0.element }

        var nextNum = (existingDumps.map { $0.num }.max() ?? 0) + 1
        // Build a quick lookup for existing pool photos by ID
        let photoByID = Dictionary(uniqueKeysWithValues: allPhotos.map { ($0.id, $0) })

        for cluster in selectedGroups {
            // 1. Resolve cluster photos → real DumpPhoto records (reuse pool, fallback to new).
            var resolvedPhotos: [DumpPhoto] = []

            for p in cluster.photos {
                if resolvedPhotos.count >= maxPhotosPerDump { break }

                if let existingID = poolPhotoMap[p.filename],
                   let existing = photoByID[existingID] {
                    resolvedPhotos.append(existing)
                } else {
                    // Fallback: shouldn't happen in pool flow.
                    let relPath = PhotoStorageManager.shared.saveImage(p.image, filename: p.filename)
                    let dp = DumpPhoto(
                        localPath: relPath,
                        filename: p.filename,
                        category: p.category,
                        labels: p.labels,
                        starred: false,
                        isHuji: FormulaEngine.detectHuji(filename: p.filename)
                    )
                    modelContext.insert(dp)
                    resolvedPhotos.append(dp)
                }
            }

            // 2. APPLY THE FORMULA — arrange photos into HOOK → CONTRAST → ... → CLOSER.
            //    arrangePhotos picks the best photo for each slot based on category scores.
            let arranged = FormulaEngine.arrangePhotos(resolvedPhotos)
            let photoIDs = arranged.map { $0.id }

            // 3. Vibe check on the real arranged photos (not stubs).
            let vibe = FormulaEngine.checkColorTemp(arranged) ? nil : "mismatch"

            // 4. Use the formula's title generator — multi-category combos beat single-cat fallbacks.
            let formulaTitle = FormulaEngine.generateDumpTitle(for: arranged)

            let dump = PhotoDump(
                num: nextNum,
                title: formulaTitle,
                photoIDs: photoIDs,
                vibeBadge: vibe,
                liked: false,
                isAIGenerated: true,
                titleApproved: nil
            )
            modelContext.insert(dump)
            nextNum += 1

            // Captions are still keyed by the Vision cluster.title (since they were generated
            // before formula re-titling). Attach them anyway — they're about the same photos.
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

