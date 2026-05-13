import SwiftUI

/// Pro-only sheet. User pastes an Instagram profile URL → backend scrubs
/// public posts → Claude distills into a style description → user reviews
/// and either replaces or appends to the current AI Style Profile.
struct ScrubInstagramSheet: View {

    @Binding var currentProfile: String
    @Environment(\.dismiss) private var dismiss

    @State private var profileURL: String = ""
    @State private var phase: Phase = .input
    @State private var result: ScrubService.ScrubResult? = nil
    @State private var errorText: String? = nil
    @State private var editableResult: String = ""

    private let gold = Color(red: 200/255, green: 169/255, blue: 110/255)

    private enum Phase { case input, scrubbing, review }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 12)

                switch phase {
                case .input:
                    inputView
                case .scrubbing:
                    scrubbingView
                case .review:
                    reviewView
                }

                Spacer()
            }
            .padding(.top, 24)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .padding(20)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 26, weight: .light))
                .foregroundColor(gold)
            Text("SCRUB INSTAGRAM")
                .font(.system(size: 11, weight: .black))
                .tracking(3)
                .foregroundColor(gold)
            Text("Distill an account's aesthetic into your AI Style Profile")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Input

    private var inputView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("INSTAGRAM PROFILE URL")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.4))

                TextField("https://instagram.com/username", text: $profileURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.1), lineWidth: 1))
            }
            .padding(.horizontal, 24)

            if let errorText {
                Text(errorText)
                    .font(.system(size: 12))
                    .foregroundColor(.red.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                start()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("SCRUB & DISTILL")
                        .font(.system(size: 13, weight: .heavy))
                        .tracking(2)
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(canStart ? gold : Color.white.opacity(0.15))
                .cornerRadius(12)
            }
            .disabled(!canStart)
            .padding(.horizontal, 24)
            .padding(.top, 4)

            // Quota indicator
            let used = ScrubService.shared.usedThisMonth()
            Text("\(ScrubService.monthlyScrubLimit - used) of \(ScrubService.monthlyScrubLimit) scrubs left this month")
                .font(.system(size: 10, weight: .medium))
                .tracking(0.5)
                .foregroundColor(.white.opacity(0.3))
                .padding(.top, 6)

            Text("Public posts only. Approximately $0.05 per scrub — included with Pro.")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.25))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
                .padding(.top, 2)
        }
    }

    private var canStart: Bool {
        let trimmed = profileURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("instagram.com") && trimmed.count > 20 && ScrubService.shared.canScrub()
    }

    // MARK: - Scrubbing (progress)

    private var scrubbingView: some View {
        VStack(spacing: 18) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(gold)
                .scaleEffect(1.3)

            Text("Scrubbing posts & distilling style...")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))

            Text("This takes 15-30 seconds.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.25))
        }
        .padding(.vertical, 40)
    }

    // MARK: - Review (editable result)

    private var reviewView: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("DISTILLED STYLE")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(2)
                        .foregroundColor(gold)
                    if let n = result?.postsAnalyzed {
                        Text("· From \(n) posts")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    Spacer()
                }

                TextEditor(text: $editableResult)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140, maxHeight: 200)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(gold.opacity(0.25), lineWidth: 1))

                if let tags = result?.hashtags, !tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(tags.prefix(6), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.45))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(5)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)

            HStack(spacing: 10) {
                Button {
                    appendToProfile()
                } label: {
                    Text("APPEND")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.4)
                        .foregroundColor(gold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .overlay(Capsule().strokeBorder(gold.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button {
                    replaceProfile()
                } label: {
                    Text("REPLACE")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.4)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(gold)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Actions

    private func start() {
        errorText = nil
        phase = .scrubbing
        let url = profileURL.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let r = try await ScrubService.shared.scrub(profileURL: url)
                await MainActor.run {
                    result = r
                    editableResult = r.description
                    phase = .review
                    HapticManager.shared.playSuccess()
                }
            } catch {
                await MainActor.run {
                    errorText = (error as? ScrubService.ScrubError)?.message ?? error.localizedDescription
                    phase = .input
                    HapticManager.shared.playWarning()
                }
            }
        }
    }

    private func replaceProfile() {
        let trimmed = editableResult.trimmingCharacters(in: .whitespacesAndNewlines)
        currentProfile = String(trimmed.prefix(750))
        HapticManager.shared.playAdded()
        dismiss()
    }

    private func appendToProfile() {
        let trimmed = editableResult.trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = (currentProfile.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + trimmed)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        currentProfile = String(combined.prefix(750))
        HapticManager.shared.playAdded()
        dismiss()
    }
}
