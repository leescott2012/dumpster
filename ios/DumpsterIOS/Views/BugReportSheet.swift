import SwiftUI
import PhotosUI

// MARK: - Bug Report Sheet (NATIVE_PORT.md §2)
//
// iOS equivalent of BugReportButton.tsx on web.
// Sends feedback to Sentry via the Envelope API — no SPM package required.
//
// To upgrade to the full Sentry SDK later:
//   1. Add https://github.com/getsentry/sentry-cocoa via Xcode → Package Dependencies
//   2. In CrashReporter.start(), uncomment the SentrySDK.start block with the DSN below
//   3. Replace SentryFeedback.submit() here with SentrySDK.capture(userFeedback:)
//   4. Delete the sendViaEnvelope() helper below

// MARK: - Feedback floating button

struct BugReportButton: View {
    @State private var showSheet = false

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    showSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "ladybug")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Report")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.75))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                }
                .padding(.trailing, 12)
                .padding(.bottom, 44) // above home indicator
            }
        }
        .sheet(isPresented: $showSheet) {
            BugReportSheet(isPresented: $showSheet)
                .presentationDetents([.medium])
        }
    }
}

// MARK: - Report sheet

struct BugReportSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject private var auth = AuthManager.shared
    @State private var message = ""
    @State private var email = ""
    @State private var isSending = false
    @State private var sent = false
    @State private var sendError: String?
    @State private var screenshotItem: PhotosPickerItem?
    @State private var screenshotData: Data?

    private let maxMessage = 1000
    private let maxScreenshotBytes = 5 * 1024 * 1024
    private var isSignedIn: Bool { auth.isSignedIn }
    private var userId: String? { auth.userId }

    var body: some View {
        NavigationStack {
            ZStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("What's going wrong?")
                    .font(.headline)
                    .padding(.top, 4)

                TextEditor(text: $message)
                    .frame(minHeight: 100)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        Group {
                            if message.isEmpty {
                                Text("Describe the issue...")
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 12)
                                    .padding(.top, 14)
                                    .allowsHitTesting(false)
                            }
                        },
                        alignment: .topLeading
                    )

                PhotosPicker(selection: $screenshotItem, matching: .images) {
                    HStack(spacing: 6) {
                        Image(systemName: "paperclip")
                        Text(screenshotData == nil ? "Attach a screenshot" : "Screenshot attached")
                        if screenshotData != nil {
                            Spacer()
                            Button {
                                screenshotItem = nil
                                screenshotData = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(screenshotData == nil ? .secondary : .primary)
                    .padding(10)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .onChange(of: screenshotItem) { _, item in
                    Task {
                        guard let item, let data = try? await item.loadTransferable(type: Data.self),
                              data.count <= maxScreenshotBytes else {
                            await MainActor.run { screenshotData = nil }
                            return
                        }
                        await MainActor.run { screenshotData = data }
                    }
                }

                if !auth.isSignedIn {
                    TextField("Email (optional — for follow-up)", text: $email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .padding(10)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                if let err = sendError {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Button(action: submit) {
                    HStack {
                        if isSending {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                        } else {
                            Text(sent ? "Sent ✓" : "Send Report")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(sent ? Color.green : Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(message.trimmingCharacters(in: .whitespaces).isEmpty || isSending || sent)

                Spacer()
            }
            .padding()
            .navigationTitle("Report a Bug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }

            // Centered confirmation — the "Sent ✓" button label alone was easy
            // to miss before the sheet auto-dismissed a moment later.
            if sent {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.green)
                    Text("Sent")
                        .font(.headline)
                }
                .padding(24)
                .background(.thickMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 12)
                .transition(.scale.combined(with: .opacity))
            }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: sent)
    }

    private func submit() {
        let trimmed = message.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSending = true
        sendError = nil

        Task {
            do {
                try await SentryFeedback.submit(
                    message: trimmed,
                    email: auth.isSignedIn ? (auth.userEmail ?? "") : email,
                    userId: userId,
                    tags: [
                        "source": "in-app-bug-button",
                        "signed_in": isSignedIn ? "true" : "false",
                        "platform": "ios",
                        "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                    ],
                    screenshot: screenshotData
                )
                await MainActor.run {
                    isSending = false
                    sent = true
                }
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                await MainActor.run { isPresented = false }
            } catch {
                await MainActor.run {
                    isSending = false
                    sendError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Sentry Envelope helper (SDK-free)
//
// Posts to Sentry's Envelope ingestion endpoint using the DSN key directly.
// This is what the JS SDK does under the hood.
// DSN: https://cac00263ad517cfa1ab22990dff35fc2@o4511424233013248.ingest.us.sentry.io/4511424250576896

enum SentryFeedback {

    private static let dsn = "https://cac00263ad517cfa1ab22990dff35fc2@o4511424233013248.ingest.us.sentry.io/4511424250576896"
    private static let projectId = "4511424250576896"
    private static let publicKey = "cac00263ad517cfa1ab22990dff35fc2"

    static func submit(
        message: String,
        email: String = "",
        userId: String? = nil,
        tags: [String: String] = [:],
        screenshot: Data? = nil
    ) async throws {
        let eventId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let timestamp = ISO8601DateFormatter().string(from: Date())

        // Sentry User Feedback event payload
        var feedbackPayload: [String: Any] = [
            "event_id": eventId,
            "timestamp": timestamp,
            "message": message,
            "level": "info",
            "platform": "cocoa",
            "sdk": ["name": "dumpster.ios.manual", "version": "1.0.0"],
        ]
        if !email.isEmpty { feedbackPayload["email"] = email }
        if let uid = userId { feedbackPayload["user"] = ["id": uid, "email": email] }
        if !tags.isEmpty { feedbackPayload["tags"] = tags.map { ["key": $0.key, "value": $0.value] } }

        guard let feedbackData = try? JSONSerialization.data(withJSONObject: feedbackPayload) else {
            throw URLError(.cannotDecodeContentData)
        }

        // Envelope header
        let envelopeHeader: [String: Any] = [
            "event_id": eventId,
            "dsn": dsn,
            "sdk": ["name": "dumpster.ios.manual", "version": "1.0.0"],
        ]
        guard let headerData = try? JSONSerialization.data(withJSONObject: envelopeHeader) else {
            throw URLError(.cannotDecodeContentData)
        }

        // Item header
        let itemHeader: [String: Any] = ["type": "event", "length": feedbackData.count]
        guard let itemHeaderData = try? JSONSerialization.data(withJSONObject: itemHeader) else {
            throw URLError(.cannotDecodeContentData)
        }

        // Assemble envelope: headerLine\nitemHeaderLine\npayloadLine
        var envelope = Data()
        envelope.append(headerData)
        envelope.append(Data("\n".utf8))
        envelope.append(itemHeaderData)
        envelope.append(Data("\n".utf8))
        envelope.append(feedbackData)

        // Optional screenshot — a second envelope item, per
        // https://develop.sentry.dev/sdk/envelopes/#attachment
        // PhotosPicker's Data transferable returns whatever format the source
        // asset actually is (JPEG/PNG/HEIC) — sniff it rather than guessing,
        // same lesson as the web MIME-mismatch bug (JAVASCRIPT-REACT-X).
        if let screenshot {
            let (ext, contentType) = sniffImageFormat(screenshot)
            let attachmentHeader: [String: Any] = [
                "type": "attachment", "length": screenshot.count,
                "filename": "screenshot.\(ext)", "content_type": contentType,
            ]
            if let attachmentHeaderData = try? JSONSerialization.data(withJSONObject: attachmentHeader) {
                envelope.append(Data("\n".utf8))
                envelope.append(attachmentHeaderData)
                envelope.append(Data("\n".utf8))
                envelope.append(screenshot)
            }
        }

        let endpoint = "https://o4511424233013248.ingest.us.sentry.io/api/\(projectId)/envelope/"
        guard let url = URL(string: endpoint) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-sentry-envelope", forHTTPHeaderField: "Content-Type")
        req.setValue("Sentry sentry_version=7, sentry_key=\(publicKey)", forHTTPHeaderField: "X-Sentry-Auth")
        req.httpBody = envelope

        let (_, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
    }

    private static func sniffImageFormat(_ data: Data) -> (ext: String, contentType: String) {
        var bytes = [UInt8](repeating: 0, count: min(12, data.count))
        data.copyBytes(to: &bytes, count: bytes.count)
        if bytes.count >= 3, bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF { return ("jpg", "image/jpeg") }
        if bytes.count >= 8, bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47 { return ("png", "image/png") }
        if bytes.count >= 12, bytes[4] == 0x66, bytes[5] == 0x74, bytes[6] == 0x79, bytes[7] == 0x70 { return ("heic", "image/heic") }
        return ("bin", "application/octet-stream")
    }
}
