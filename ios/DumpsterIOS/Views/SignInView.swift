import SwiftUI

// MARK: - Sign-In View
//
// Magic link (email OTP) sign-in — the ONLY auth method allowed per NATIVE_PORT.md §8.
// Password-based auth is PROHIBITED.

struct SignInView: View {
    @ObservedObject private var auth = AuthManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var code = ""
    @FocusState private var emailFocused: Bool
    @FocusState private var codeFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            ZStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.black)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.black.opacity(0.05)))
                    }
                    Spacer()
                }
                Text("Log in")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.black)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ScrollView {
                if auth.magicLinkSent {
                    // Code entry — the email link often opens in the mail app's own
                    // browser instead of handing off to us, so the 6-digit code from
                    // the same email is the reliable way to finish signing in.
                    VStack(spacing: 16) {
                        Image(systemName: "envelope.badge.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.black.opacity(0.6))
                        Text("Check your email")
                            .font(.headline)
                            .foregroundColor(.black)
                        Text("Enter the 6-digit code we sent to\n\(email)")
                            .font(.subheadline)
                            .foregroundColor(.black.opacity(0.55))
                            .multilineTextAlignment(.center)

                        TextField("123456", text: $code)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .focused($codeFocused)
                            .font(.system(size: 28, weight: .semibold, design: .monospaced))
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .foregroundColor(.black)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.black.opacity(0.15), lineWidth: 1)
                            )
                            .onChange(of: code) { _, newValue in
                                let digits = newValue.filter(\.isNumber)
                                code = String(digits.prefix(6))
                                if code.count == 6 { verifyCode() }
                            }

                        if let err = auth.authError {
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        if auth.isSigningIn {
                            ProgressView().progressViewStyle(.circular)
                        }

                        Button("Use a different email") {
                            auth.magicLinkSent = false
                            auth.authError = nil
                            email = ""
                            code = ""
                        }
                        .font(.footnote)
                        .foregroundColor(.black.opacity(0.45))
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 40)
                    .onAppear { codeFocused = true }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.black)

                        TextField("your@email.com", text: $email)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .focused($emailFocused)
                            .padding()
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .foregroundColor(.black)
                            .font(.system(size: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.black.opacity(0.15), lineWidth: 1)
                            )

                        Text("We'll email you a code to sign in.")
                            .font(.system(size: 13))
                            .foregroundColor(.black.opacity(0.5))

                        if let err = auth.authError {
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        Button(action: sendLink) {
                            HStack {
                                if auth.isSigningIn {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .scaleEffect(0.85)
                                        .tint(.white)
                                } else {
                                    Text("Continue")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(isValidEmail ? Color.black : Color.black.opacity(0.15))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(!isValidEmail || auth.isSigningIn)
                        .padding(.top, 20)

                        HStack {
                            Rectangle().fill(Color.black.opacity(0.1)).frame(height: 1)
                            Text("Or").font(.system(size: 14)).foregroundColor(.black.opacity(0.4))
                            Rectangle().fill(Color.black.opacity(0.1)).frame(height: 1)
                        }
                        .padding(.vertical, 20)

                        Button(action: signInWithGoogle) {
                            HStack(spacing: 10) {
                                Text("G")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.black)
                                Text("Continue with Google")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.black)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.black.opacity(0.15), lineWidth: 1)
                            )
                        }
                        .disabled(auth.isSigningIn)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                }
            }

            Spacer()

            Text("By continuing you agree to Dumpster's\nTerms of Service and Privacy Policy")
                .font(.caption2)
                .foregroundColor(.black.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.bottom, 24)
        }
        .background(Color(white: 0.97).ignoresSafeArea())
        .onAppear { emailFocused = true }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn { dismiss() }
        }
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

    private func signInWithGoogle() {
        emailFocused = false
        Task { await auth.signInWithGoogle() }
    }

    private func verifyCode() {
        codeFocused = false
        Task { await auth.verifyEmailCode(email: email, code: code) }
    }
}
