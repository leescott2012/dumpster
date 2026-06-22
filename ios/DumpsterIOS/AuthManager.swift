import Foundation
import SwiftUI
import Security

// MARK: - Auth Manager
//
// Manages Supabase sign-in via magic link (email OTP).
// Stores the session in the iOS Keychain.
//
// Security rules (NATIVE_PORT.md §8):
// - userId is NEVER read from request bodies — always pulled from the stored JWT.
// - Password-based auth is PROHIBITED. Only magic link / OAuth / passwordless.
// - EXIF GPS data is never logged or sent to Sentry.

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

    // MARK: - Keychain keys
    private static let keychainService = "com.leescott.dumpster.ios.auth"
    private static let sessionKey = "supabase_session"

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

    /// Step 2: called from onOpenURL when the app receives `dumpster://auth/callback?token_hash=...`.
    func handleCallback(url: URL) async {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let tokenHash = components.queryItems?.first(where: { $0.name == "token_hash" })?.value
        else { return }

        isSigningIn = true
        authError = nil
        defer { isSigningIn = false }

        do {
            let newSession = try await SupabaseClient.shared.verifyOTP(tokenHash: tokenHash)
            session = newSession
            saveSessionToKeychain(newSession)
            magicLinkSent = false

            // Fire AI profile sync now that we have a userId from the JWT
            await AIProfileSync.shared.syncOnSignIn(userId: newSession.userId,
                                                    jwt: newSession.accessToken)
            CrashReporter.shared.setUser(id: newSession.userId)
            Analytics.track(.sessionStart)
        } catch {
            authError = error.localizedDescription
            CrashReporter.shared.capture(error, tags: ["action": "magic_link_callback"])
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
