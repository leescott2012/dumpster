import SwiftUI
import SwiftData
import MapKit

/// Full-screen photo overlay shown when `appState.lightboxPhotoId != nil`.
/// Tap backdrop or X button to dismiss.
struct LightboxView: View {

    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query private var allPhotos: [DumpPhoto]
    @State private var showInfo = false

    private var photo: DumpPhoto? {
        guard let id = appState.lightboxPhotoId else { return nil }
        return allPhotos.first { $0.id == id }
    }

    var body: some View {
        if let photo = photo {
            ZStack {
                Color.black.opacity(0.92)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }

                VStack(spacing: 0) {
                    HStack {
                        // (i) info toggle — mirrors web PhotoLightbox
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { showInfo.toggle() }
                        } label: {
                            Image(systemName: showInfo ? "info.circle.fill" : "info.circle")
                                .font(.system(size: 26))
                                .foregroundColor(showInfo ? appState.accentColor : .white.opacity(0.75))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .padding(.leading, 20)
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.white.opacity(0.75))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .padding(.trailing, 20)
                    }
                    // 70pt clears the Dynamic Island / status bar reliably — matches
                    // FileCabinetMenuView's cabinetHeader, which uses the same value.
                    // The prior `.padding(20)` (20pt top) left the button underneath
                    // that safe-area band, where taps don't reach the app.
                    .padding(.top, 70)

                    Spacer()

                    if let img = PhotoStorageManager.shared.loadImage(relativePath: photo.localPath) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 16)
                            // Swipe up to reveal metadata, swipe down to hide it —
                            // matches Apple Photos' lightbox gesture; the (i) button
                            // above remains as an equivalent tap target.
                            .gesture(
                                DragGesture(minimumDistance: 24)
                                    .onEnded { value in
                                        if value.translation.height < -60 && !showInfo {
                                            withAnimation(.easeInOut(duration: 0.2)) { showInfo = true }
                                        } else if value.translation.height > 60 && showInfo {
                                            withAnimation(.easeInOut(duration: 0.2)) { showInfo = false }
                                        }
                                    }
                            )
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 80))
                            .foregroundColor(.white.opacity(0.3))
                    }

                    HStack(spacing: 12) {
                        Text(photo.category.uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.0)
                            .foregroundColor(appState.accentColor)
                        Text(photo.filename)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if photo.isHuji {
                            Text("HUJI")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundColor(.red)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.18))
                                .cornerRadius(4)
                        }
                    }
                    .padding(.top, 14)
                    .padding(.horizontal, 20)

                    if showInfo {
                        ScrollView {
                            PhotoInfoPanel(photo: photo)
                        }
                        .frame(maxHeight: 320)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    Spacer()
                }
            }
            .transition(.opacity)
            .onChange(of: appState.lightboxPhotoId) { showInfo = false }
        }
    }

    private func dismiss() {
        withAnimation(.easeInOut(duration: 0.22)) {
            appState.lightboxPhotoId = nil
        }
    }
}

/// Apple-Photos-style metadata card — port of web PhotoInfoPanel.tsx.
/// Every section is conditional; photos without EXIF just show filename
/// + a fallback line, same as web.
struct PhotoInfoPanel: View {

    let photo: DumpPhoto

    private var hasAnyExif: Bool {
        photo.takenAt != nil || photo.camera != nil || photo.iso != nil
            || photo.focalLength != nil || photo.fStop != nil
            || photo.shutterSpeed != nil || (photo.lat != nil && photo.lng != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Date / filename header
            if let takenAt = photo.takenAt {
                Text(Self.formatDate(takenAt))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.bottom, 4)
            }
            Text(photo.filename)
                .font(.system(size: 12))
                .foregroundColor(Color(white: 0.53))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.bottom, 14)

            // Camera block
            if photo.camera != nil || photo.imageFormat != nil || photo.fileSize != nil || photo.pixelWidth != nil {
                VStack(alignment: .leading, spacing: 6) {
                    if let camera = photo.camera {
                        HStack {
                            Text(camera)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                            Spacer()
                            if let format = photo.imageFormat {
                                Text(format)
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(1.0)
                                    .foregroundColor(Color(white: 0.67))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color(white: 0.12))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(white: 0.16), lineWidth: 1))
                                    .cornerRadius(6)
                            }
                        }
                        .padding(.bottom, 2)
                    }
                    if photo.lens != nil || photo.focalLength != nil || photo.fStop != nil {
                        Text(lensLine)
                            .font(.system(size: 12))
                            .foregroundColor(Color(white: 0.67))
                    }
                    if photo.pixelWidth != nil || photo.fileSize != nil {
                        Text(dimensionsLine)
                            .font(.system(size: 12))
                            .foregroundColor(Color(white: 0.53))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(white: 0.08))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(white: 0.12), lineWidth: 1))
                .cornerRadius(12)
                .padding(.bottom, 12)
            }

            // Exposure stat row
            if photo.iso != nil || photo.focalLength != nil || photo.fStop != nil || photo.shutterSpeed != nil {
                HStack(spacing: 8) {
                    if let iso = photo.iso { statCell(label: "ISO", value: String(iso)) }
                    if let fl = photo.focalLength { statCell(label: nil, value: "\(Int(fl.rounded())) mm") }
                    if let fStop = photo.fStop { statCell(label: nil, value: String(format: "ƒ/%.2f", fStop)) }
                    if let shutter = photo.shutterSpeed { statCell(label: nil, value: Self.formatShutter(shutter)) }
                }
                .padding(.bottom, 12)
            }

            // Location
            if let lat = photo.lat, let lng = photo.lng {
                VStack(alignment: .leading, spacing: 0) {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                    ))) {
                        Marker("", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng))
                    }
                    .frame(height: 160)
                    .allowsHitTesting(false)
                    Text(String(format: "%.4f°, %.4f°", lat, lng))
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.67))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
                .background(Color(white: 0.08))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(white: 0.12), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if !hasAnyExif {
                Text("No EXIF data — this photo was likely a screenshot, edited, or stripped.")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.54))
                    .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color(white: 0.055))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(white: 0.12), lineWidth: 1))
        .cornerRadius(12)
    }

    private var lensLine: String {
        var parts: [String] = []
        if let lens = photo.lens { parts.append(lens) }
        var optics: [String] = []
        if let fl = photo.focalLength { optics.append("\(Int(fl.rounded())) mm") }
        if let fStop = photo.fStop { optics.append(String(format: "ƒ/%.2f", fStop)) }
        if !optics.isEmpty { parts.append(optics.joined(separator: " ")) }
        return parts.joined(separator: " — ")
    }

    private var dimensionsLine: String {
        var parts: [String] = []
        if let w = photo.pixelWidth, let h = photo.pixelHeight {
            parts.append(String(format: "%.1f MP", Double(w * h) / 1_000_000))
            parts.append("\(w)×\(h)")
        }
        if let size = photo.fileSize { parts.append(Self.formatFileSize(size)) }
        return parts.joined(separator: " · ")
    }

    private func statCell(label: String?, value: String) -> some View {
        VStack(spacing: 2) {
            if let label {
                Text(label)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.0)
                    .foregroundColor(Color(white: 0.54))
            }
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(white: 0.91))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color(white: 0.08))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.12), lineWidth: 1))
        .cornerRadius(8)
    }

    // MARK: - Formatters (match web PhotoInfoPanel.tsx)

    static func formatDate(_ date: Date) -> String {
        let day = date.formatted(.dateTime.weekday(.abbreviated))
        let dateStr = date.formatted(.dateTime.month(.abbreviated).day().year())
        let time = date.formatted(.dateTime.hour().minute())
        return "\(day) · \(dateStr) · \(time)"
    }

    static func formatShutter(_ s: Double) -> String {
        if s >= 1 { return String(format: "%.1f s", s) }
        return "1/\(Int((1 / s).rounded())) s"
    }

    static func formatFileSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }
}
