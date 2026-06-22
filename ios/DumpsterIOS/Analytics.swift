import Foundation

// MARK: - Analytics
//
// Native twin of the web's client/src/lib/analytics.ts. Fire-and-forget event
// tracking that inserts rows directly into the shared Supabase `activity_log`
// table, so native usage shows up in the GENIUSS admin dashboard
// (/api/admin-stats) alongside web usage. The RLS policy
// `users_insert_own_activity` permits auth.uid() = user_id, so no backend
// endpoint is required.
//
// The dashboard consumes exactly three events (NATIVE_PORT.md §11):
//   session_start    — once per app launch / sign-in            (drives DAU)
//   photo_uploaded   — after photos land in the pool   { count: n }
//   dump_exported    — after a dump is shared/exported  { photo_count: n }
//
// Rules (mirror analytics.ts):
//   - Never blocks the UI — always fired from a detached background Task.
//   - Silently no-ops when signed out.
//   - Skips the owner account so dev usage stays out of the data.
//   - Errors are swallowed — telemetry is best-effort, never user-facing.

enum AnalyticsEvent: String {
    case sessionStart  = "session_start"
    case photoUploaded = "photo_uploaded"
    case dumpExported  = "dump_exported"
}

enum Analytics {

    /// Owner's Supabase user UUID — excluded from analytics to match the web's
    /// IS_OWNER exclusion (mirrors the server's ADMIN_USER_ID). Leave empty to
    /// track everyone. (leescott2019@gmail.com — the dashboard admin account.)
    private static let ownerUserID = "77517979-e0c7-4427-8afd-cc006e906df5"

    /// Fire an analytics event. Safe to call from any thread or actor.
    static func track(_ event: AnalyticsEvent, metadata: [String: Any]? = nil) {
        Task.detached(priority: .background) {
            // AuthManager is @MainActor — read identity on the main actor.
            let (userID, jwt) = await MainActor.run {
                (AuthManager.shared.userId, AuthManager.shared.jwt)
            }
            guard let userID = userID, let jwt = jwt else { return }   // signed out → no-op
            if !ownerUserID.isEmpty && userID == ownerUserID { return } // keep owner out

            // Always tag platform so the dashboard can tell native from web.
            var meta: [String: Any] = ["platform": "ios"]
            if let metadata = metadata { meta.merge(metadata) { _, new in new } }
            let row: [String: Any] = ["user_id": userID, "event": event.rawValue, "metadata": meta]

            guard let url = URL(string: "\(SupabaseClient.url)/rest/v1/activity_log"),
                  let body = try? JSONSerialization.data(withJSONObject: row) else { return }

            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            SupabaseClient.shared.authHeaders(jwt: jwt).forEach { req.setValue($1, forHTTPHeaderField: $0) }
            req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
            req.httpBody = body
            _ = try? await URLSession.shared.data(for: req)
        }
    }
}
