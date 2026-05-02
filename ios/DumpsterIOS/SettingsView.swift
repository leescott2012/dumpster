import SwiftUI

// MARK: - Settings View

/// Provides configuration for the Dumpster app, including OpenAI API key management,
/// cache controls, and app information.

struct SettingsView: View {
    @Binding var isPresented: Bool
    @State private var apiKeyInput: String = ""
    @State private var isKeyVisible = false
    @State private var showSavedConfirmation = false

    @ObservedObject private var captionService = CaptionService.shared

    private let gold = Color(red: 200/255, green: 169/255, blue: 110/255)

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // Header
                    HStack {
                        Text("SETTINGS")
                            .font(.system(size: 12, weight: .black))
                            .tracking(3)
                            .foregroundColor(gold)
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 60)
                    .padding(.bottom, 28)

                    // API Key Section
                    sectionHeader("OPENAI API KEY")

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Required for AI caption generation. Your key is stored locally on this device.")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.4))
                            .lineSpacing(4)

                        HStack(spacing: 12) {
                            Group {
                                if isKeyVisible {
                                    TextField("sk-...", text: $apiKeyInput)
                                } else {
                                    SecureField("sk-...", text: $apiKeyInput)
                                }
                            }
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(14)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )

                            Button {
                                isKeyVisible.toggle()
                            } label: {
                                Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.4))
                                    .frame(width: 44, height: 44)
                                    .background(Color.white.opacity(0.06))
                                    .cornerRadius(10)
                            }
                        }

                        HStack(spacing: 12) {
                            Button {
                                captionService.apiKey = apiKeyInput
                                showSavedConfirmation = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    showSavedConfirmation = false
                                }
                            } label: {
                                Text(showSavedConfirmation ? "SAVED" : "SAVE KEY")
                                    .font(.system(size: 11, weight: .bold))
                                    .tracking(2)
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(showSavedConfirmation ? Color.green : gold)
                                    .cornerRadius(8)
                            }

                            if captionService.hasAPIKey {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 6, height: 6)
                                    Text("Key configured")
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                            }

                            Spacer()

                            if !apiKeyInput.isEmpty {
                                Button {
                                    apiKeyInput = ""
                                    captionService.apiKey = ""
                                } label: {
                                    Text("CLEAR")
                                        .font(.system(size: 11, weight: .bold))
                                        .tracking(1)
                                        .foregroundColor(.red.opacity(0.7))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(Color.red.opacity(0.1))
                                        .cornerRadius(8)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)

                    // Cache Section
                    sectionHeader("CACHE")

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Clear temporary AI analysis files to free up storage.")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.4))
                            .lineSpacing(4)

                        Button {
                            clearAICache()
                        } label: {
                            Text("CLEAR AI CACHE")
                                .font(.system(size: 11, weight: .bold))
                                .tracking(2)
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)

                    // About Section
                    sectionHeader("ABOUT")

                    VStack(alignment: .leading, spacing: 8) {
                        infoRow("Version", value: "1.0.0")
                        infoRow("Build", value: "2025.05")
                        infoRow("Vision AI", value: "Apple VNClassifyImageRequest")
                        infoRow("Captions", value: captionService.hasAPIKey ? "OpenAI GPT-4.1-nano" : "Local fallback")
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)

                    // Production Note
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 12))
                                .foregroundColor(.yellow.opacity(0.7))
                            Text("PRODUCTION NOTE")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1)
                                .foregroundColor(.yellow.opacity(0.7))
                        }
                        Text("For production, migrate API key storage to iOS Keychain and consider using a server-side proxy to avoid embedding keys in the app.")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.3))
                            .lineSpacing(4)
                    }
                    .padding(16)
                    .background(Color.yellow.opacity(0.05))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.yellow.opacity(0.15), lineWidth: 1)
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 60)
                }
            }

            // Close Button
            Button {
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
        }
        .preferredColorScheme(.dark)
        .onAppear {
            let currentKey = captionService.apiKey
            if !currentKey.isEmpty {
                apiKeyInput = currentKey
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold))
            .tracking(2)
            .foregroundColor(.white.opacity(0.25))
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))
            Spacer()
            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.vertical, 4)
    }

    private func clearAICache() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dumpster_ai")
        try? FileManager.default.removeItem(at: tempDir)
    }
}
