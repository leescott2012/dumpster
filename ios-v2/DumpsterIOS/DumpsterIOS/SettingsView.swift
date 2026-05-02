import SwiftUI

// MARK: - Settings View (Legacy — Redirects to File Cabinet)

/// This view is kept for backward compatibility with the existing fullScreenCover presentation.
/// It now serves as a lightweight redirect that opens the File Cabinet menu.
/// The actual settings UI lives in FileCabinetMenuView → AISettingsTabView.

struct SettingsView: View {
    @Binding var isPresented: Bool
    @State private var apiKeyInput: String = ""
    @State private var isKeyVisible = false
    @State private var showSavedConfirmation = false

    @ObservedObject private var llmService = LLMService.shared

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

                    // Redirect Banner
                    VStack(spacing: 16) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 36, weight: .light))
                            .foregroundColor(gold.opacity(0.5))

                        Text("Settings have moved!")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)

                        Text("All settings are now in the File Cabinet menu.\nLong-press the Dynamic Island or tap the menu icon to open it.")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.4))
                            .multilineTextAlignment(.center)
                            .lineSpacing(5)
                            .padding(.horizontal, 16)

                        Button {
                            isPresented = false
                        } label: {
                            Text("GOT IT")
                                .font(.system(size: 13, weight: .bold))
                                .tracking(3)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(gold)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)

                    // Quick API Key Section (for convenience)
                    sectionHeader("QUICK API KEY SETUP")

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Quickly add an OpenAI API key. For more providers, use the File Cabinet menu.")
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
                                // Save to LLMService (OpenAI provider)
                                llmService.setAPIKey(apiKeyInput, for: .openai)
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

                            if llmService.hasAPIKey(for: .openai) {
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
                                    llmService.setAPIKey("", for: .openai)
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

                    // Connected Providers
                    sectionHeader("CONNECTED PROVIDERS")

                    VStack(spacing: 6) {
                        ForEach(LLMService.LLMProvider.allCases) { provider in
                            HStack(spacing: 10) {
                                Image(systemName: provider.iconName)
                                    .font(.system(size: 12))
                                    .foregroundColor(llmService.hasAPIKey(for: provider) ? gold : .white.opacity(0.2))
                                    .frame(width: 24)

                                Text(provider.displayName)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))

                                Spacer()

                                if llmService.hasAPIKey(for: provider) {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 5, height: 5)
                                        Text("Connected")
                                            .font(.system(size: 10))
                                            .foregroundColor(.green.opacity(0.7))
                                    }
                                } else {
                                    Text("Not connected")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.2))
                                }
                            }
                            .padding(.vertical, 6)
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
                        infoRow("AI Provider", value: llmService.preferredProvider()?.displayName ?? "Local fallback")
                        if let provider = llmService.preferredProvider() {
                            infoRow("Model", value: llmService.selectedModel(for: provider))
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
            let currentKey = llmService.apiKey(for: .openai)
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
