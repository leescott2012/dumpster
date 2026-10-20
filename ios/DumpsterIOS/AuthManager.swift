import Foundation
import SwiftUI
import Security
import AuthenticationServices

// MARK: - Auth Manager
//
// Manages Supabase sign-in via magic link (email OTP) and OAuth (Google).
// Stores the session in the iOS Keychain.
//
// Security rules (NATIVE_PORT.md §8):
// - userId is NEVER read from request bodies — always pulled from the stored JWT.
// - Password-based auth is PROHIBITED. Only magic link / OAuth / passwordless.
// - EXIF GPS data is never logged or sent to Sentry.

/// Anchors the system OAuth browser sheet to the app's key window.
private final class WebAuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

@MainActor
final class AuthManager: ObservableObject {

    // MARK: - Singleton
    static let shared = AuthManager()

    // MARK: - Published
    @Published private(set) var session: SupabaseSession?
    @Published var isSigningIn = false
    @Published var magicLinkSent = false
    @Published var authError: String?

    var isSignedIn: Bool { session != nil }
    var userId: String? { session?.userId }
    var userEmail: String? { session?.email }
    var jwt: String? { session?.accessToken }
    var userPhone: String? { session?.phone }

    /// True once we've confirmed with the server (refresh/sign-in this launch) that
    /// the signed-in account has no verified phone. Avoids flashing the gate at launch
    /// for accounts that already verified on web.
    @Published private(set) var phoneStatusKnown = false
    var needsPhone: Bool { phoneStatusKnown && isSignedIn && (session?.phone ?? "").isEmpty }

    // MARK: - Keychain keys
    private static let keychainService = "com.leescott.dumpster.ios.auth"
    private static let sessionKey = "supabase_session"

    // MARK: - OAuth
    private let webAuthContextProvider = WebAuthContextProvider()
    private var webAuthSession: ASWebAuthenticationSession?

    private init() {
        // Restore persisted session on launch
        if let stored = loadSessionFromKeychain() {
            session = stored
            // Proactively refresh in background — tokens expire, refresh never does (until rotated)
            Task { await silentRefresh() }
        }
    }

    // MARK: - Magic Link Sign-In

    /// Step 1: request a magic link for `email`. Shows spinner while sending.
    func sendMagicLink(email: String) async {
        isSigningIn = true
        authError = nil
        defer { isSigningIn = false }
        do {
            try await SupabaseClient.shared.sendMagicLink(email: email)
            magicLinkSent = true
        } catch {
            authError = error.localizedDescription
        }
    }

    /// Step 2: called from onOpenURL when the app receives the magic link callback.
    ///
    /// This can arrive in two different shapes depending on the Supabase email
    /// template config, and we can't assume which one is live in the dashboard:
    ///   1. `dumpster://auth/callback?token_hash=...&type=...` — template uses
    ///      `{{ .TokenHash }}` directly (Supabase's documented native deep-link
    ///      pattern). We verify the token_hash ourselves.
    ///   2. `dumpster://auth/callback#access_token=...&refresh_token=...` — template
    ///      still uses the default `{{ .ConfirmationURL }}`, which verifies
    ///      server-side and redirects back with tokens already issued (same
    ///      shape as the OAuth callback).
    /// Previously only (1) was handled and everything else was silently dropped —
    /// a tap on the email link would look like it did nothing.
    func handleCallback(url: URL) async {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }

        if let tokenHash = components.queryItems?.first(where: { $0.name == "token_hash" })?.value {
            // "email" is the generic OTP type Supabase's own docs use for token_hash
            // links (and what verifyEmailOTP already uses for the 6-digit code path)
            // — fall back to it unless the link itself specifies a different type.
            let type = components.queryItems?.first(where: { $0.name == "type" })?.value ?? "email"
            isSigningIn = true
            authError = nil
            defer { isSigningIn = false }
            do {
                let newSession = try await SupabaseClient.shared.verifyOTP(tokenHash: tokenHash, type: type)
                await completeSignIn(newSession)
            } catch {
                authError = error.localizedDescription
                CrashReporter.shared.capture(error, tags: ["action": "magic_link_callback"])
            }
            return
        }

        if url.fragment != nil {
            isSigningIn = true
            authError = nil
            defer { isSigningIn = false }
            do {
                let newSession = try await SupabaseClient.shared.session(fromOAuthCallback: url)
                await completeSignIn(newSession)
            } catch {
                authError = error.localizedDescription
                CrashReporter.shared.capture(error, tags: ["action": "magic_link_callback"])
            }
            return
        }

        // Neither shape matched — surface it instead of failing silently.
        authError = "That sign-in link is missing its token. Try the 6-digit code from the email instead."
    }

    /// Alternative to the deep-link callback: user types the 6-digit code from the
    /// email instead of tapping the link (mail apps often open links in an in-app
    /// browser instead of handing off to us, so the code is the reliable path).
    func verifyEmailCode(email: String, code: String) async {
        isSigningIn = true
        authError = nil
        defer { isSigningIn = false }

        do {
            let newSession = try await SupabaseClient.shared.verifyEmailOTP(email: email, token: code)
            await completeSignIn(newSession)
        } catch {
            authError = error.localizedDescription
            CrashReporter.shared.capture(error, tags: ["action": "email_code_verify"])
        }
    }

    // MARK: - Phone verification (returns an error message, or nil on success)

    /// mode .signIn: sign in / sign up by phone. mode .add: attach a phone to the signed-in account.
    func sendPhoneCode(phone: String, adding: Bool) async -> String? {
        do {
            if adding {
                guard let jwt = jwt else { return "Sign in first." }
                try await SupabaseClient.shared.addPhone(phone: phone, jwt: jwt)
            } else {
                try await SupabaseClient.shared.sendPhoneOTP(phone: phone)
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func verifyPhoneCode(phone: String, code: String, adding: Bool) async -> String? {
        do {
            if adding {
                guard let jwt = jwt else { return "Sign in first." }
                try await SupabaseClient.shared.verifyPhoneChange(phone: phone, token: code, jwt: jwt)
                await silentRefresh()   // pulls the now-verified phone into the session; the gate goes away
            } else {
                await completeSignIn(try await SupabaseClient.shared.verifyPhoneOTP(phone: phone, token: code))
            }
            return nil
        } catch {
            CrashReporter.shared.capture(error, tags: ["action": adding ? "phone_add_verify" : "phone_signin_verify"])
            return error.localizedDescription
        }
    }

    private func completeSignIn(_ newSession: SupabaseSession) async {
        session = newSession
        phoneStatusKnown = true
        saveSessionToKeychain(newSession)
        magicLinkSent = false

        await AIProfileSync.shared.syncOnSignIn(userId: newSession.userId,
                                                jwt: newSession.accessToken)
        CrashReporter.shared.setUser(id: newSession.userId)
        Analytics.track(.sessionStart)
    }

    // MARK: - Google Sign-In (OAuth via system browser sheet)

    /// Opens Google's sign-in page in a system browser sheet, then completes the
    /// same way handleCallback does for magic link. No Google SDK / client ID
    /// needed on our end — Supabase already brokers Google OAuth (same config
    /// web's AuthContext.tsx uses).
    func signInWithGoogle() async { await oauthSignIn(provider: "google") }

    /// Same browser-sheet flow as Google; Supabase brokers Apple (already enabled for the web app).
    func signInWithApple() async { await oauthSignIn(provider: "apple") }

    private func oauthSignIn(provider: String) async {
        guard let authorizeURL = SupabaseClient.shared.oauthAuthorizeURL(provider: provider) else {
            authError = "Could not build \(provider.capitalized) sign-in URL."
            return
        }

        isSigningIn = true
        authError = nil
        defer { isSigningIn = false }

        do {
            let callbackURL = try await startWebAuth(url: authorizeURL)
            let newSession = try await SupabaseClient.shared.session(fromOAuthCallback: callbackURL)
            await completeSignIn(newSession)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // User dismissed the sheet — not a real error, stay quiet.
        } catch {
            authError = error.localizedDescription
            CrashReporter.shared.capture(error, tags: ["action": "\(provider)_oauth"])
        }
    }

    private func startWebAuth(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let authSession = ASWebAuthenticationSession(url: url, callbackURLScheme: "dumpster") { [weak self] callbackURL, error in
                self?.webAuthSession = nil
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? SupabaseClient.SupabaseError.decodeFailed("No callback URL."))
                }
            }
            authSession.presentationContextProvider = webAuthContextProvider
            authSession.prefersEphemeralWebBrowserSession = false
            webAuthSession = authSession
            authSession.start()
        }
    }

    // MARK: - Sign Out

    func signOut() async {
        if let jwt = jwt {
            await SupabaseClient.shared.signOut(jwt: jwt)
        }
        session = nil
        deleteSessionFromKeychain()
        CrashReporter.shared.setUser(id: nil)
    }

    // MARK: - Token Refresh

    /// Silently refresh using stored refresh token. Call on app foreground.
    func silentRefresh() async {
        guard let stored = session else { return }
        do {
            let refreshed = try await SupabaseClient.shared.refreshSession(refreshToken: stored.refreshToken)
            session = refreshed
            saveSessionToKeychain(refreshed)
            phoneStatusKnown = true
        } catch {
            // Refresh failed → session is dead, clear it
            session = nil
            deleteSessionFromKeychain()
        }
    }

    // MARK: - Keychain persistence

    private func saveSessionToKeychain(_ s: SupabaseSession) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.keychainService,
            kSecAttrAccount: Self.sessionKey,
        ]
        SecItemDelete(query as CFDictionary)
        let attrs = query.merging([kSecValueData: data]) { $1 }
        SecItemAdd(attrs as CFDictionary, nil)
    }

    private func loadSessionFromKeychain() -> SupabaseSession? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.keychainService,
            kSecAttrAccount: Self.sessionKey,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let session = try? JSONDecoder().decode(SupabaseSession.self, from: data)
        else { return nil }
        return session
    }

    private func deleteSessionFromKeychain() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.keychainService,
            kSecAttrAccount: Self.sessionKey,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
