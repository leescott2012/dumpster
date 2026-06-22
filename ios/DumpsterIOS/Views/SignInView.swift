import SwiftUI

// MARK: - Sign-In View
//
// Magic link (email OTP) sign-in — the ONLY auth method allowed per NATIVE_PORT.md §8.
// Password-based auth is PROHIBITED.

struct SignInView: View {
    @ObservedObject private var auth = AuthManager.shared
    @State private var email = ""
    @FocusState private var emailFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo / wordmark
            VStack(spacing: 8) {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.white)
                Text("DUMPSTER")
                    .font(.system(size: 28, weight: .black, design: .default))
                    .tracking(6)
                    .foregroundColor(.white)
                Text("your photo dump, elevated")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.45))
            }
            .padding(.bottom, 48)

            if auth.magicLinkSent {
                // Confirmation state
                VStack(spacing: 16) {
                    Image(systemName: "envelope.badge.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.7))
                    Text("Check your email")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("We sent a sign-in link to\n\(email)")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                    Button("Use a different email") {
                        auth.magicLinkSent = false
                        email = ""
                    }
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.45))
                }
                .padding(.horizontal, 32)
            } else {
                // Email entry
                VStack(spacing: 12) {
                    TextField("your@email.com", text: $email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .focused($emailFocused)
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .foregroundColor(.white)
                        .font(.system(size: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )

                    if let err = auth.authError {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red.opacity(0.85))
                    }

                    Button(action: sendLink) {
                        HStack {
                            if auth.isSigningIn {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.85)
                                    .tint(.black)
                            } else {
                                Text("Send Sign-In Link")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(isValidEmail ? Color.white : Color.white.opacity(0.25))
                        .foregroundColor(isValidEmail ? .black : .white.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!isValidEmail || auth.isSigningIn)
                }
                .padding(.horizontal, 32)
            }

            Spacer()

            Text("By continuing you agree to our\nTerms of Service and Privacy Policy")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.3))
                .multilineTextAlignment(.center)
                .padding(.bottom, 32)
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear { emailFocused = true }
    }

    private var isValidEmail: Bool {
        let e = email.trimmingCharacters(in: .whitespaces)
        return e.contains("@") && e.contains(".")
    }

    private func sendLink() {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        emailFocused = false
        Task { await auth.sendMagicLink(email: trimmed) }
    }
}
