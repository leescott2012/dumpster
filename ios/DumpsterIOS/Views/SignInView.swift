import SwiftUI

// MARK: - Sign-In View
//
// Magic link (email OTP) sign-in — the ONLY auth method allowed per NATIVE_PORT.md §8.
// Password-based auth is PROHIBITED.

// MARK: - Dark tokens (match Theme.swift: black surface, #C8A96E gold)

private enum DK {
    static let bg = Color(red: 10/255, green: 10/255, blue: 10/255)
    static let field = Color.white.opacity(0.07)
    static let stroke = Color.white.opacity(0.14)
    static let text = Color(red: 232/255, green: 232/255, blue: 232/255)
    static let text2 = Color(red: 153/255, green: 153/255, blue: 153/255)
    static let gold = Color(red: 200/255, green: 169/255, blue: 110/255)
    static let radius: CGFloat = 12
}

private extension View {
    func dkField() -> some View {
        self.font(.body)
            .foregroundColor(DK.text)
            .tint(DK.gold)
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(DK.field)
            .clipShape(RoundedRectangle(cornerRadius: DK.radius))
            .overlay(RoundedRectangle(cornerRadius: DK.radius).stroke(DK.stroke, lineWidth: 1))
    }
    func dkPrimary(enabled: Bool) -> some View {
        self.font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(enabled ? DK.gold : DK.gold.opacity(0.25))
            .foregroundColor(enabled ? .black : DK.text2)
            .clipShape(RoundedRectangle(cornerRadius: DK.radius))
    }
}

/// US numbers by default: 10 digits -> +1XXXXXXXXXX; anything starting with + is used as typed.
private func normalizedE164(_ raw: String) -> String? {
    let t = raw.trimmingCharacters(in: .whitespaces)
    let digits = t.filter(\.isNumber)
    if t.hasPrefix("+") { return digits.count >= 8 ? "+" + digits : nil }
    if digits.count == 11 && digits.hasPrefix("1") { return "+" + digits }
    return digits.count == 10 ? "+1" + digits : nil
}

private func dkPrompt(_ s: String) -> Text { Text(s).foregroundColor(DK.text2) }

private struct DKDivider: View {
    let label: String
    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(DK.stroke).frame(height: 1)
            Text(label).font(.footnote).foregroundColor(DK.text2).fixedSize()
            Rectangle().fill(DK.stroke).frame(height: 1)
        }
    }
}

struct SignInView: View {
    @ObservedObject private var auth = AuthManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var identifier = ""          // one box: phone or email
    @State private var email = ""
    @State private var code = ""
    @State private var phoneFlow = false
    @FocusState private var emailFocused: Bool
    @FocusState private var codeFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(DK.text)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .accessibilityLabel("Back")
                Spacer()
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
                            .foregroundColor(DK.gold)
                        Text("Check your email")
                            .font(.title2.weight(.bold))
                            .foregroundColor(DK.text)
                        Text("Enter the 6-digit code we sent to\n\(email)")
                            .font(.subheadline)
                            .foregroundColor(DK.text2)
                            .multilineTextAlignment(.center)

                        TextField("123456", text: $code, prompt: dkPrompt("123456"))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .focused($codeFocused)
                            .font(.system(size: 28, weight: .semibold, design: .monospaced))
                            .foregroundColor(DK.text)
                            .tint(DK.gold)
                            .frame(minHeight: 56)
                            .background(DK.field)
                            .clipShape(RoundedRectangle(cornerRadius: DK.radius))
                            .overlay(RoundedRectangle(cornerRadius: DK.radius).stroke(DK.stroke, lineWidth: 1))
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
                            ProgressView().progressViewStyle(.circular).tint(DK.gold)
                        }

                        Button("Use a different email") {
                            auth.magicLinkSent = false
                            auth.authError = nil
                            email = ""
                            identifier = ""
                            code = ""
                        }
                        .font(.footnote)
                        .foregroundColor(DK.text2)
                        .frame(minHeight: 44)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 40)
                    .onAppear { codeFocused = true }
                } else if phoneFlow {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Enter your code")
                            .font(.title2.weight(.bold))
                            .foregroundColor(DK.text)
                        PhoneCodeForm(adding: false, lockedHint: "Use Apple, Google or email instead.",
                                      initialPhone: identifier, autoSend: true)
                        Button("Use a different number or email") {
                            phoneFlow = false
                            identifier = ""
                            emailFocused = true
                        }
                        .font(.footnote)
                        .foregroundColor(DK.text2)
                        .frame(minHeight: 44)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 32)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Log in")
                            .font(.largeTitle.weight(.bold))
                            .foregroundColor(DK.text)
                        Text("Sign in or create an account. No password needed.")
                            .font(.subheadline)
                            .foregroundColor(DK.text2)
                            .padding(.top, 6)
                            .padding(.bottom, 24)

                        Button(action: signInWithApple) {
                            HStack(spacing: 10) {
                                Image(systemName: "apple.logo")
                                Text("Continue with Apple")
                            }
                            .font(.body.weight(.semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: DK.radius))
                        }
                        .disabled(auth.isSigningIn)

                        Button(action: signInWithGoogle) {
                            HStack(spacing: 10) {
                                Text("G").font(.body.weight(.bold))
                                Text("Continue with Google").font(.body.weight(.semibold))
                            }
                            .foregroundColor(DK.text)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(DK.field)
                            .clipShape(RoundedRectangle(cornerRadius: DK.radius))
                            .overlay(RoundedRectangle(cornerRadius: DK.radius).stroke(DK.stroke, lineWidth: 1))
                        }
                        .disabled(auth.isSigningIn)
                        .padding(.top, 10)

                        DKDivider(label: "or").padding(.vertical, 20)

                        TextField("Phone or email", text: $identifier, prompt: dkPrompt("Phone or email"))
                            .keyboardType(.emailAddress)       // shows @ and digits; phone numbers are still easy to type
                            .textContentType(.username)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .submitLabel(.continue)
                            .focused($emailFocused)
                            .onSubmit { continueTapped() }
                            .dkField()

                        if let err = auth.authError {
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.top, 8)
                        }

                        Button(action: continueTapped) {
                            HStack {
                                if auth.isSigningIn {
                                    ProgressView().progressViewStyle(.circular).tint(.black)
                                } else {
                                    Text("Continue")
                                }
                            }
                            .dkPrimary(enabled: canContinue)
                        }
                        .disabled(!canContinue || auth.isSigningIn)
                        .padding(.top, 14)

                        Text("We'll text or email you a 6-digit code.")
                            .font(.footnote)
                            .foregroundColor(DK.text2)
                            .padding(.top, 10)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 16)
                }
            }
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: 2) {
                Text("By continuing you agree to Dumpster's")
                    .foregroundColor(DK.text2)
                HStack(spacing: 4) {
                    Link("Terms of Service", destination: URL(string: "https://dumpster-web-manus.vercel.app/terms")!)
                    Text("and").foregroundColor(DK.text2)
                    Link("Privacy Policy", destination: URL(string: "https://dumpster-web-manus.vercel.app/privacy")!)
                }
                .tint(DK.gold)
            }
            .font(.caption2)
            .multilineTextAlignment(.center)
            .padding(.vertical, 12)
        }
        .background(DK.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { emailFocused = true }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn { dismiss() }
        }
    }

    private var idTrimmed: String { identifier.trimmingCharacters(in: .whitespaces) }
    private var isEmailInput: Bool { idTrimmed.contains("@") }
    private var canContinue: Bool {
        isEmailInput ? (idTrimmed.contains(".") && idTrimmed.count > 4) : normalizedE164(idTrimmed) != nil
    }

    /// One box: "@" means email code, otherwise a phone number.
    private func continueTapped() {
        guard canContinue else { return }
        emailFocused = false
        if isEmailInput {
            email = idTrimmed
            Task { await auth.sendMagicLink(email: idTrimmed) }
        } else {
            phoneFlow = true
        }
    }

    private func signInWithApple() {
        emailFocused = false
        Task { await auth.signInWithApple() }
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
    var initialPhone: String = ""   // sign-in screen passes the number already typed
    var autoSend: Bool = false      // ...and sends the code right away

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

    private var e164: String? { normalizedE164(phone) }

    var body: some View {
        VStack(spacing: 10) {
            if locked && !codeStage {
                Text("Too many codes requested. Try again in about \(minutesLeft) min. \(lockedHint)")
                    .font(.footnote)
                    .foregroundColor(DK.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(DK.field)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                TextField("Phone number", text: $phone, prompt: dkPrompt("Phone number"))
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .disabled(codeStage || busy)
                    .dkField()

                if codeStage {
                    TextField("6-digit code", text: $code, prompt: dkPrompt("6-digit code"))
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .disabled(busy)
                        .onChange(of: code) { _, v in
                            code = String(v.filter(\.isNumber).prefix(6))
                            if code.count == 6 && !busy { Task { await verify() } }   // auto-submit
                        }
                        .dkField()
                }

                Button(action: { Task { codeStage ? await verify() : await send() } }) {
                    HStack {
                        if busy { ProgressView().tint(.black) }
                        Text(codeStage ? "Verify code" : "Text me a code")
                    }
                    .dkPrimary(enabled: canSubmit)
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
                    .foregroundColor(DK.text2)
                    .frame(minHeight: 44)
                    if locked { Text("Code limit reached. \(lockedHint)").font(.footnote).foregroundColor(DK.text2) }
                }
            }

            if let error = error {
                Text(error).font(.caption).foregroundColor(.red).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task {
            if autoSend && phone.isEmpty && !initialPhone.isEmpty {
                phone = initialPhone
                await send()
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
            Image(systemName: "phone.badge.checkmark").font(.system(size: 36)).foregroundColor(DK.gold)
            Text("Verify your phone").font(.title2.weight(.bold)).foregroundColor(DK.text)
            Text("Add a phone number to keep your account secure. We'll text you a 6-digit code.")
                .font(.subheadline).foregroundColor(DK.text2).multilineTextAlignment(.center)
            PhoneCodeForm(adding: true, lockedHint: "Sign out below and sign in a different way, or try again later.")
            Button("Sign out") { Task { await auth.signOut() } }
                .font(.footnote).foregroundColor(DK.text2).frame(minHeight: 44)
            Spacer()
        }
        .padding(24)
        .background(DK.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
