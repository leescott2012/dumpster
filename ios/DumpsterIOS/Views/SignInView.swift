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

                        HStack {
                            Rectangle().fill(Color.black.opacity(0.1)).frame(height: 1)
                            Text("Or use phone").font(.system(size: 14)).foregroundColor(.black.opacity(0.4)).fixedSize()
                            Rectangle().fill(Color.black.opacity(0.1)).frame(height: 1)
                        }
                        .padding(.vertical, 20)

                        PhoneCodeForm(adding: false, lockedHint: "Use email or Google above instead.")
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                }
            }

            Spacer()

            VStack(spacing: 2) {
                Text("By continuing you agree to Dumpster's")
                    .foregroundColor(.black.opacity(0.4))
                HStack(spacing: 4) {
                    Link("Terms of Service", destination: URL(string: "https://dumpster-web-manus.vercel.app/terms")!)
                    Text("and").foregroundColor(.black.opacity(0.4))
                    Link("Privacy Policy", destination: URL(string: "https://dumpster-web-manus.vercel.app/privacy")!)
                }
            }
            .font(.caption2)
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


// MARK: - Phone code form (shared by sign-in and the verify gate)
//
// Limits (per device, 1 hour): 3 codes sent, 30s between sends, 3 wrong guesses per code.
// Resend and "change number" both count as a send. Supabase rate-limits server-side too.

struct PhoneCodeForm: View {
    let adding: Bool            // true = attach phone to the signed-in account; false = sign in by phone
    let lockedHint: String

    @ObservedObject private var auth = AuthManager.shared
    @State private var phone = ""
    @State private var code = ""
    @State private var codeStage = false
    @State private var busy = false
    @State private var error: String?
    @State private var cooldown = 0
    @State private var wrong = 0
    @State private var sends: [Double] = PhoneCodeForm.recentSends()

    private static let maxSends = 3
    private static let maxWrong = 3
    private static let windowSecs: Double = 3600
    private static let cooldownSecs = 30
    private static let key = "dumpster_otp_sends"

    private static func recentSends() -> [Double] {
        let all = (UserDefaults.standard.array(forKey: key) as? [Double]) ?? []
        return all.filter { Date().timeIntervalSince1970 - $0 < windowSecs }
    }

    private var locked: Bool { sends.count >= Self.maxSends }
    private var minutesLeft: Int {
        guard let first = sends.first else { return 1 }
        return max(1, Int(ceil((first + Self.windowSecs - Date().timeIntervalSince1970) / 60)))
    }

    /// US numbers by default: 10 digits -> +1XXXXXXXXXX; anything starting with + is used as typed.
    private var e164: String? {
        let t = phone.trimmingCharacters(in: .whitespaces)
        let digits = t.filter(\.isNumber)
        if t.hasPrefix("+") { return "+" + digits }
        if digits.count == 11 && digits.hasPrefix("1") { return "+" + digits }
        return digits.count == 10 ? "+1" + digits : nil
    }

    var body: some View {
        VStack(spacing: 10) {
            if locked && !codeStage {
                Text("Too many codes requested. Try again in about \(minutesLeft) min. \(lockedHint)")
                    .font(.footnote)
                    .foregroundColor(.black.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.black.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                TextField("Phone number", text: $phone, prompt: Text("Phone number").foregroundColor(.black.opacity(0.4)))
                    .foregroundColor(.black)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .disabled(codeStage || busy)
                    .padding(14)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.15), lineWidth: 1))

                if codeStage {
                    TextField("6-digit code", text: $code, prompt: Text("6-digit code").foregroundColor(.black.opacity(0.4)))
                        .foregroundColor(.black)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .disabled(busy)
                        .onChange(of: code) { _, v in code = String(v.filter(\.isNumber).prefix(6)) }
                        .padding(14)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.15), lineWidth: 1))
                }

                Button(action: { Task { codeStage ? await verify() : await send() } }) {
                    HStack {
                        if busy { ProgressView().tint(.white) }
                        Text(codeStage ? "Verify code" : "Text me a code")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(canSubmit ? Color.black : Color.black.opacity(0.15))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!canSubmit || busy)

                if codeStage {
                    HStack {
                        Button(cooldown > 0 ? "Resend code in \(cooldown)s" : (locked ? "No more resends" : "Resend code")) {
                            Task { await send() }
                        }
                        .disabled(busy || cooldown > 0 || locked)
                        Spacer()
                        Button("Wrong number? Change it") {
                            codeStage = false; code = ""; error = nil
                        }
                    }
                    .font(.footnote)
                    .foregroundColor(.black.opacity(0.5))
                    if locked { Text("Code limit reached. \(lockedHint)").font(.footnote).foregroundColor(.black.opacity(0.5)) }
                }
            }

            if let error = error {
                Text(error).font(.caption).foregroundColor(.red).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: cooldown) {
            guard cooldown > 0 else { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if !Task.isCancelled { cooldown -= 1 }
        }
    }

    private var canSubmit: Bool { codeStage ? code.count == 6 : e164 != nil }

    private func send() async {
        error = nil
        guard let number = e164 else { error = "Enter a valid phone number, like 404 555 1234."; return }
        if Self.recentSends().count >= Self.maxSends { sends = Self.recentSends(); return }
        busy = true
        let err = await auth.sendPhoneCode(phone: number, adding: adding)
        busy = false
        if let err = err { error = err; return }
        UserDefaults.standard.set(Self.recentSends() + [Date().timeIntervalSince1970], forKey: Self.key)
        sends = Self.recentSends()
        code = ""; wrong = 0; cooldown = Self.cooldownSecs; codeStage = true
    }

    private func verify() async {
        error = nil
        guard let number = e164 else { return }
        busy = true
        let err = await auth.verifyPhoneCode(phone: number, code: code, adding: adding)
        busy = false
        guard err != nil else { return }   // success: sign-in view dismisses / gate disappears on its own
        wrong += 1
        code = ""
        if wrong >= Self.maxWrong {
            codeStage = false
            error = "Too many wrong codes. Request a new code."
        } else {
            error = "That code didn't work (\(Self.maxWrong - wrong) tries left)."
        }
    }
}

// MARK: - Phone gate: blocks the app until the signed-in account has a verified phone

struct PhoneGateView: View {
    @ObservedObject private var auth = AuthManager.shared

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Verify your phone").font(.system(size: 24, weight: .bold))
            Text("Add a phone number to keep your account secure. We'll text you a 6-digit code.")
                .font(.subheadline).foregroundColor(.black.opacity(0.6)).multilineTextAlignment(.center)
            PhoneCodeForm(adding: true, lockedHint: "Sign out below and sign in a different way, or try again later.")
            Button("Sign out") { Task { await auth.signOut() } }
                .font(.footnote).foregroundColor(.black.opacity(0.4)).padding(.top, 8)
            Spacer()
        }
        .padding(24)
        .background(Color(white: 0.97).ignoresSafeArea())
    }
}
