import SwiftUI
import LocalAuthentication
import CommonCrypto

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
    @State private var inUse = false      // adding a phone another account already owns
    @State private var reported = false
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
            if inUse {
                Text("That number is already linked to another Dumpster account. If it's yours, send this to us and we'll match it to this account.")
                    .font(.footnote)
                    .foregroundColor(DK.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(DK.field)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Button(action: { reportPhoneInUse() }) {
                    Text(reported ? "Sent. We'll sort it out." : "This is my number: send to support")
                        .dkPrimary(enabled: !reported)
                }
                .disabled(reported)
                Button("Use a different number") { inUse = false; codeStage = false; phone = ""; error = nil }
                    .font(.footnote).foregroundColor(DK.text2)
            } else if locked && !codeStage {
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

    /// Files a bug-bin report (same endpoint the web app uses) so the number can be matched to this account.
    private func reportPhoneInUse() {
        reported = true
        let number = e164 ?? phone
        Task {
            guard let url = URL(string: "https://dumpster-web-manus.vercel.app/api/bug-report") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let jwt = AuthManager.shared.jwt { req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization") }
            let body: [String: Any] = [
                "source": "phone-in-use",
                "message": "Can't verify phone: number already used by another account",
                "user_agent": "Dumpster iOS",
                "context": ["phone": number, "note": "User says the number is theirs; link or free it for their signed-in account."],
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            _ = try? await URLSession.shared.data(for: req)
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
        if let err = err {
            if adding, err.range(of: "already|registered|exists|in use|taken", options: [.regularExpression, .caseInsensitive]) != nil {
                inUse = true
            } else {
                error = err
            }
            return
        }
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


// MARK: - PIN lock: a 4-digit PIN (or Face ID) that unlocks the app on THIS device
//
// Never signs anyone in by itself — it only gates an already signed-in session, so it can't be
// guessed from another device. Salted PBKDF2 hash in the Keychain. 3 wrong = 30s wait, 4 = 60s,
// 5 = PIN wiped and the user must sign in again with a code. Re-locks after 5 min in the background.

@MainActor
final class PinLock: ObservableObject {
    static let shared = PinLock()

    @Published private(set) var unlocked = false
    @Published private(set) var revision = 0     // bump so views re-read after set/remove/dismiss

    enum Result { case ok, wrong(remaining: Int, waitSeconds: Int), forceSignOut }

    private struct Rec: Codable { var salt: String; var hash: String; var fails: Int; var lockedUntil: Double }
    private let service = "com.leescott.dumpster.ios.pin"
    private let maxFails = 5
    private var uid: String? { AuthManager.shared.userId }

    var hasPin: Bool { uid.flatMap { read($0) } != nil }
    var setupDismissed: Bool { uid.map { UserDefaults.standard.bool(forKey: "dumpster_pin_dismissed_\($0)") } ?? true }
    /// Signed in, phone verified, but no PIN yet and hasn't said "Not now".
    var needsSetup: Bool { AuthManager.shared.isSignedIn && !AuthManager.shared.needsPhone && !hasPin && !setupDismissed }
    var needsUnlock: Bool { AuthManager.shared.isSignedIn && !AuthManager.shared.needsPhone && hasPin && !unlocked }
    var showGate: Bool { _ = revision; return needsSetup || needsUnlock }

    func markUnlocked() { unlocked = true; revision += 1 }
    func relock() { if hasPin { unlocked = false; revision += 1 } }
    func dismissSetup() { if let u = uid { UserDefaults.standard.set(true, forKey: "dumpster_pin_dismissed_\(u)") }; revision += 1 }

    func setPin(_ pin: String) {
        guard let u = uid else { return }
        var saltBytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, 16, &saltBytes)
        let salt = Data(saltBytes)
        write(u, Rec(salt: salt.base64EncodedString(), hash: derive(pin, salt: salt), fails: 0, lockedUntil: 0))
        unlocked = true; revision += 1
    }

    func removePin() { if let u = uid { delete(u) }; unlocked = false; revision += 1 }

    func verify(_ pin: String) -> Result {
        guard let u = uid, var r = read(u), let salt = Data(base64Encoded: r.salt) else { return .forceSignOut }
        let wait = Int(ceil(r.lockedUntil - Date().timeIntervalSince1970))
        if wait > 0 { return .wrong(remaining: maxFails - r.fails, waitSeconds: wait) }
        if derive(pin, salt: salt) == r.hash { r.fails = 0; r.lockedUntil = 0; write(u, r); markUnlocked(); return .ok }
        r.fails += 1
        if r.fails >= maxFails { delete(u); return .forceSignOut }
        let waitSecs = r.fails >= 4 ? 60 : (r.fails >= 3 ? 30 : 0)
        r.lockedUntil = waitSecs > 0 ? Date().timeIntervalSince1970 + Double(waitSecs) : 0
        write(u, r)
        return .wrong(remaining: maxFails - r.fails, waitSeconds: waitSecs)
    }

    // Face ID / Touch ID: convenience unlock only (a PIN must exist first).
    func tryBiometrics() async {
        guard hasPin else { return }
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else { return }
        if (try? await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Unlock Dumpster")) == true {
            markUnlocked()
        }
    }

    // MARK: PBKDF2 + Keychain
    private func derive(_ pin: String, salt: Data) -> String {
        var out = [UInt8](repeating: 0, count: 32)
        let pw = Array(pin.utf8)
        let saltBytes = [UInt8](salt)
        _ = pw.withUnsafeBufferPointer { pwp in
            pwp.baseAddress!.withMemoryRebound(to: Int8.self, capacity: pw.count) { p in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), p, pw.count, saltBytes, saltBytes.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 150_000, &out, 32)
            }
        }
        return out.map { String(format: "%02x", $0) }.joined()
    }
    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    private func read(_ account: String) -> Rec? {
        var q = query(account); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(Rec.self, from: data)
    }
    private func write(_ account: String, _ rec: Rec) {
        guard let data = try? JSONEncoder().encode(rec) else { return }
        SecItemDelete(query(account) as CFDictionary)
        var q = query(account)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }
    private func delete(_ account: String) { SecItemDelete(query(account) as CFDictionary) }
}

struct PinGateView: View {
    @ObservedObject private var pin = PinLock.shared
    @ObservedObject private var auth = AuthManager.shared
    @State private var digits = ""
    @State private var first = ""
    @State private var choosing = true          // setup: false while confirming
    @State private var error: String?
    @State private var wait = 0

    private var setupMode: Bool { pin.needsSetup }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Text(setupMode ? (choosing ? "Set a 4-digit PIN" : "Confirm your PIN") : "Enter your PIN")
                .font(.title2.weight(.bold)).foregroundColor(DK.text)
            if setupMode && choosing {
                Text("Unlock Dumpster quickly on this device. You'll still use a code to sign in on a new device.")
                    .font(.footnote).foregroundColor(DK.text2).multilineTextAlignment(.center).padding(.horizontal, 40)
            }
            HStack(spacing: 14) {
                ForEach(0..<4, id: \.self) { i in
                    Circle().stroke(DK.gold, lineWidth: 1.5).background(Circle().fill(i < digits.count ? DK.gold : .clear)).frame(width: 14, height: 14)
                }
            }
            Text(wait > 0 ? "Too many tries. Wait \(wait)s." : (error ?? " "))
                .font(.footnote).foregroundColor(.red).frame(minHeight: 18)

            VStack(spacing: 14) {
                ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]], id: \.self) { row in
                    HStack(spacing: 14) { ForEach(row, id: \.self) { key($0) } }
                }
                HStack(spacing: 14) {
                    if !setupMode {
                        Button { Task { await pin.tryBiometrics() } } label: {
                            Image(systemName: "faceid").font(.title2).foregroundColor(DK.gold).frame(width: 72, height: 72)
                        }.accessibilityLabel("Unlock with Face ID")
                    } else { Color.clear.frame(width: 72, height: 72) }
                    key("0")
                    Button { if !digits.isEmpty { digits.removeLast() } } label: {
                        Image(systemName: "delete.left").font(.title3).foregroundColor(DK.text).frame(width: 72, height: 72)
                    }.accessibilityLabel("Delete")
                }
            }
            .opacity(wait > 0 ? 0.4 : 1).disabled(wait > 0)

            if setupMode {
                Button("Not now") { pin.dismissSetup() }.font(.footnote).foregroundColor(DK.text2).padding(.top, 8)
            } else {
                Button("Forgot PIN? Sign in with a code") { pin.removePin(); Task { await auth.signOut() } }
                    .font(.footnote).foregroundColor(DK.text2).padding(.top, 8)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DK.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task { if !setupMode { await pin.tryBiometrics() } }
        .task(id: wait) {
            guard wait > 0 else { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if !Task.isCancelled { wait -= 1 }
        }
    }

    private func key(_ d: String) -> some View {
        Button { press(d) } label: {
            Text(d).font(.system(size: 28)).foregroundColor(DK.text)
                .frame(width: 72, height: 72).background(DK.field).clipShape(Circle())
                .overlay(Circle().stroke(DK.stroke, lineWidth: 1))
        }
    }

    private func press(_ d: String) {
        guard wait == 0, digits.count < 4 else { return }
        digits += d
        guard digits.count == 4 else { return }
        let entered = digits
        digits = ""
        if setupMode {
            if choosing { first = entered; choosing = false; error = nil; return }
            if entered == first { pin.setPin(entered) } else { error = "PINs didn't match. Try again."; first = ""; choosing = true }
            return
        }
        switch pin.verify(entered) {
        case .ok: error = nil
        case .forceSignOut: Task { await auth.signOut() }          // 5 wrong PINs: back to a full code sign-in
        case .wrong(let remaining, let waitSeconds): wait = waitSeconds; error = "Wrong PIN. \(remaining) tries left."
        }
    }
}
