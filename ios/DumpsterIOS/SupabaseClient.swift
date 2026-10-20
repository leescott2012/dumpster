import Foundation

// MARK: - Supabase REST Client
//
// Thin URLSession wrapper around Supabase's PostgREST + Auth APIs.
// No SPM package required — uses the public REST API directly.
//
// To replace with the official Supabase Swift SDK later:
//   1. Add https://github.com/supabase/supabase-swift via Xcode → Package Dependencies
//   2. Replace usages of SupabaseClient.shared with SupabaseClient (SDK client)
//   3. Delete this file

final class SupabaseClient {

    // MARK: - Singleton
    static let shared = SupabaseClient()

    // MARK: - Config
    static let url = "https://zstsigakqcggerhjbawj.supabase.co"
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpzdHNpZ2FrcWNnZ2VyaGpiYXdqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg5Njg5OTUsImV4cCI6MjA5NDU0NDk5NX0.u7rE6Txr89qWgTKc9UTinnzmGdCBeIT_e2HpYKjXOcs"

    private init() {}

    // MARK: - Errors

    enum SupabaseError: LocalizedError {
        case noSession
        case httpError(Int, String)
        case decodeFailed(String)
        case noRow   // PostgREST PGRST116 equivalent

        var errorDescription: String? {
            switch self {
            case .noSession:              return "Not signed in."
            case .httpError(let c, let m): return "\(Self.friendlyMessage(from: m) ?? m) (HTTP \(c))"
            case .decodeFailed(let m):    return "Decode error: \(m)"
            case .noRow:                  return "No row found."
            }
        }

        /// Supabase error bodies are JSON like {"error_code":"over_email_send_rate_limit","msg":"..."}.
        /// Pull the human-readable field out so the UI shows "email rate limit exceeded"
        /// instead of a raw JSON blob. Returns nil (falls back to the raw body) if it's
        /// not JSON in the shape we expect.
        static func friendlyMessage(from body: String) -> String? {
            guard let data = body.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return (json["msg"] as? String) ?? (json["error_description"] as? String) ?? (json["error"] as? String)
        }
    }

    // MARK: - Auth helpers

    /// Headers for authenticated PostgREST requests.
    func authHeaders(jwt: String) -> [String: String] {
        [
            "apikey": Self.anonKey,
            "Authorization": "Bearer \(jwt)",
            "Content-Type": "application/json",
        ]
    }

    /// Headers for unauthenticated requests (sign-in flow).
    var anonHeaders: [String: String] {
        [
            "apikey": Self.anonKey,
            "Content-Type": "application/json",
        ]
    }

    // MARK: - Generic REST

    /// GET /rest/v1/<table>?<query>
    /// Returns the raw JSON data, or throws SupabaseError.noRow if 0 results with single().
    func get(table: String, query: String, jwt: String) async throws -> Data {
        let urlStr = "\(Self.url)/rest/v1/\(table)?\(query)"
        guard let url = URL(string: urlStr) else { throw SupabaseError.decodeFailed("bad url") }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        authHeaders(jwt: jwt).forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.setValue("application/vnd.pgrst.object+json", forHTTPHeaderField: "Accept") // single obj
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse {
            if http.statusCode == 406 { throw SupabaseError.noRow }   // PGRST116 via Accept header
            if http.statusCode == 404 {
                // Check PostgREST error code in body
                if let body = try? JSONDecoder().decode([String: String].self, from: data),
                   body["code"] == "PGRST116" { throw SupabaseError.noRow }
            }
            guard (200..<300).contains(http.statusCode) else {
                let msg = String(data: data, encoding: .utf8) ?? "unknown"
                throw SupabaseError.httpError(http.statusCode, msg)
            }
        }
        return data
    }

    /// POST /rest/v1/<table> with upsert support.
    func upsert(table: String, body: [String: Any], jwt: String) async throws {
        let urlStr = "\(Self.url)/rest/v1/\(table)"
        guard let url = URL(string: urlStr) else { return }
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        authHeaders(jwt: jwt).forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        req.httpBody = bodyData
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "unknown"
            throw SupabaseError.httpError(http.statusCode, msg)
        }
    }

    // MARK: - Auth: Magic Link (OTP)

    /// Sends a magic link email. The user taps it and is redirected to the app via deep link.
    func sendMagicLink(email: String) async throws {
        let urlStr = "\(Self.url)/auth/v1/otp"
        guard let url = URL(string: urlStr) else { return }
        let body: [String: Any] = [
            "email": email,
            "create_user": true,
            "options": ["emailRedirectTo": "dumpster://auth/callback"]
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        anonHeaders.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.httpBody = bodyData
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "unknown"
            throw SupabaseError.httpError(http.statusCode, msg)
        }
    }

    /// Exchange the token_hash from a deep link callback for a session.
    /// Call this from `onOpenURL` when the magic link fires.
    /// Default type is "email" — the generic OTP type Supabase's own native
    /// deep-linking docs use for token_hash links, which also matches what
    /// verifyEmailOTP below already uses for the 6-digit code path. "magiclink"
    /// is a narrower type that only matches tokens Supabase categorized that
    /// way; if the incoming link doesn't have its own `type` param, "email" is
    /// the safer generic match.
    func verifyOTP(tokenHash: String, type: String = "email") async throws -> SupabaseSession {
        let urlStr = "\(Self.url)/auth/v1/verify"
        guard let url = URL(string: urlStr) else { throw SupabaseError.decodeFailed("bad url") }
        let body: [String: Any] = ["token_hash": tokenHash, "type": type]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            throw SupabaseError.decodeFailed("encode fail")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        anonHeaders.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.httpBody = bodyData
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "unknown"
            throw SupabaseError.httpError((resp as? HTTPURLResponse)?.statusCode ?? 0, msg)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String,
              let user = json["user"] as? [String: Any],
              let userId = user["id"] as? String,
              let email = user["email"] as? String
        else {
            throw SupabaseError.decodeFailed("session parse failed")
        }
        return SupabaseSession(accessToken: accessToken, refreshToken: refreshToken,
                               userId: userId, email: email)
    }

    /// Exchange the 6-digit code the user typed in from the email for a session.
    /// Same endpoint as verifyOTP, but by `token` (the short code) + `email` instead
    /// of `token_hash` — this is what lets sign-in work without the deep link firing.
    func verifyEmailOTP(email: String, token: String) async throws -> SupabaseSession {
        let urlStr = "\(Self.url)/auth/v1/verify"
        guard let url = URL(string: urlStr) else { throw SupabaseError.decodeFailed("bad url") }
        let body: [String: Any] = ["email": email, "token": token, "type": "email"]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            throw SupabaseError.decodeFailed("encode fail")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        anonHeaders.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.httpBody = bodyData
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "unknown"
            throw SupabaseError.httpError((resp as? HTTPURLResponse)?.statusCode ?? 0, msg)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String,
              let user = json["user"] as? [String: Any],
              let userId = user["id"] as? String,
              let userEmail = user["email"] as? String
        else {
            throw SupabaseError.decodeFailed("session parse failed")
        }
        return SupabaseSession(accessToken: accessToken, refreshToken: refreshToken,
                               userId: userId, email: userEmail)
    }

    // MARK: - Auth: phone (SMS code via Twilio Verify, configured in Supabase)

    /// POST/PUT JSON to an /auth/v1 path. `jwt` nil = anonymous (sign-in), set = acting as the signed-in user.
    private func authJSON(_ method: String, path: String, body: [String: Any], jwt: String? = nil) async throws -> Data {
        guard let url = URL(string: "\(Self.url)\(path)"),
              let bodyData = try? JSONSerialization.data(withJSONObject: body)
        else { throw SupabaseError.decodeFailed("bad request") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        (jwt.map { authHeaders(jwt: $0) } ?? anonHeaders).forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.httpBody = bodyData
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "unknown"
            throw SupabaseError.httpError((resp as? HTTPURLResponse)?.statusCode ?? 0, msg)
        }
        return data
    }

    /// Code requests go through our server so the 3-per-hour limit is enforced per account
    /// (clearing the app or switching devices can't reset it). Verifying still goes straight to Supabase.
    private func requestCodeViaServer(phone: String, mode: String, jwt: String? = nil) async throws {
        guard let url = URL(string: "https://dumpster-web-manus.vercel.app/api/otp-send"),
              let bodyData = try? JSONSerialization.data(withJSONObject: ["channel": "phone", "identifier": phone, "mode": mode])
        else { throw SupabaseError.decodeFailed("bad request") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let jwt = jwt { req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization") }
        req.httpBody = bodyData
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "unknown"
            throw SupabaseError.httpError((resp as? HTTPURLResponse)?.statusCode ?? 0, msg)
        }
    }

    /// Sign-in: text a 6-digit code to `phone` (E.164, e.g. +14045551234). Creates the account if new.
    func sendPhoneOTP(phone: String) async throws {
        try await requestCodeViaServer(phone: phone, mode: "signin")
    }

    /// Sign-in: verify the texted code and return a session.
    func verifyPhoneOTP(phone: String, token: String) async throws -> SupabaseSession {
        let data = try await authJSON("POST", path: "/auth/v1/verify", body: ["phone": phone, "token": token, "type": "sms"])
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String,
              let user = json["user"] as? [String: Any],
              let userId = user["id"] as? String
        else { throw SupabaseError.decodeFailed("session parse failed") }
        return SupabaseSession(accessToken: accessToken, refreshToken: refreshToken,
                               userId: userId, email: (user["email"] as? String) ?? "",
                               phone: (user["phone"] as? String) ?? phone)
    }

    /// Signed-in account without a phone: attach one. Texts a code to `phone`.
    func addPhone(phone: String, jwt: String) async throws {
        try await requestCodeViaServer(phone: phone, mode: "add", jwt: jwt)
    }

    /// Confirm the code for addPhone; the verified number is then stored on the account.
    func verifyPhoneChange(phone: String, token: String, jwt: String) async throws {
        _ = try await authJSON("POST", path: "/auth/v1/verify", body: ["phone": phone, "token": token, "type": "phone_change"], jwt: jwt)
    }

    /// Refresh an expired access token using the refresh token.
    func refreshSession(refreshToken: String) async throws -> SupabaseSession {
        let urlStr = "\(Self.url)/auth/v1/token?grant_type=refresh_token"
        guard let url = URL(string: urlStr) else { throw SupabaseError.decodeFailed("bad url") }
        let body: [String: Any] = ["refresh_token": refreshToken]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            throw SupabaseError.decodeFailed("encode fail")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        anonHeaders.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.httpBody = bodyData
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "unknown"
            throw SupabaseError.httpError((resp as? HTTPURLResponse)?.statusCode ?? 0, msg)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let newRefresh = json["refresh_token"] as? String,
              let user = json["user"] as? [String: Any],
              let userId = user["id"] as? String
        else {
            throw SupabaseError.decodeFailed("refresh parse failed")
        }
        return SupabaseSession(accessToken: accessToken, refreshToken: newRefresh,
                               userId: userId, email: (user["email"] as? String) ?? "",
                               phone: user["phone"] as? String)
    }

    // MARK: - Auth: OAuth (Google, etc.)

    /// Builds the Supabase OAuth authorize URL for `provider`. Open this in an
    /// ASWebAuthenticationSession; Supabase redirects back to
    /// dumpster://auth/callback#access_token=...&refresh_token=...
    func oauthAuthorizeURL(provider: String, redirectTo: String = "dumpster://auth/callback") -> URL? {
        var components = URLComponents(string: "\(Self.url)/auth/v1/authorize")
        components?.queryItems = [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "redirect_to", value: redirectTo),
        ]
        return components?.url
    }

    /// Parses the access/refresh tokens out of an OAuth callback URL's fragment
    /// and resolves the signed-in user, producing the same session shape as verifyOTP.
    func session(fromOAuthCallback url: URL) async throws -> SupabaseSession {
        guard let fragment = url.fragment else {
            throw SupabaseError.decodeFailed("no fragment in OAuth callback")
        }
        let params = URLComponents(string: "?\(fragment)")?.queryItems ?? []
        guard let accessToken = params.first(where: { $0.name == "access_token" })?.value,
              let refreshToken = params.first(where: { $0.name == "refresh_token" })?.value
        else {
            let errorDesc = params.first(where: { $0.name == "error_description" })?.value
            throw SupabaseError.httpError(0, errorDesc ?? "OAuth callback missing tokens")
        }
        let (userId, email, phone) = try await fetchUser(accessToken: accessToken)
        return SupabaseSession(accessToken: accessToken, refreshToken: refreshToken,
                               userId: userId, email: email, phone: phone)
    }

    /// GET /auth/v1/user — resolves id/email for an access token (OAuth callbacks
    /// don't include the user object inline the way verify/token responses do).
    private func fetchUser(accessToken: String) async throws -> (id: String, email: String, phone: String?) {
        guard let url = URL(string: "\(Self.url)/auth/v1/user") else {
            throw SupabaseError.decodeFailed("bad url")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "unknown"
            throw SupabaseError.httpError((resp as? HTTPURLResponse)?.statusCode ?? 0, msg)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String
        else {
            throw SupabaseError.decodeFailed("user parse failed")
        }
        return (id, (json["email"] as? String) ?? "", json["phone"] as? String)
    }

    /// Sign out — invalidates the server session.
    func signOut(jwt: String) async {
        guard let url = URL(string: "\(Self.url)/auth/v1/logout") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        authHeaders(jwt: jwt).forEach { req.setValue($1, forHTTPHeaderField: $0) }
        _ = try? await URLSession.shared.data(for: req)
    }
}

// MARK: - Session value type

struct SupabaseSession: Codable {
    let accessToken: String
    let refreshToken: String
    let userId: String
    let email: String
    /// Verified phone on the Supabase user; nil/empty until the account verifies one.
    var phone: String? = nil
}
