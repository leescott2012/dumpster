import SwiftUI
import SwiftData

@main
struct DumpsterApp: App {

    init() {
        CrashReporter.shared.start()
        // Opens the current account's own local data (see AccountData.swift) before any view exists.
        _ = AccountSwitcher.shared
    }

    var body: some Scene {
        WindowGroup { AccountRoot() }
    }
}

/// App root. Rebuilds from scratch (new SwiftData container, fresh view state) whenever the signed-in
/// account changes, so one account never sees another account's local data and no restart is needed.
private struct AccountRoot: View {
    @ObservedObject private var accounts = AccountSwitcher.shared
    @ObservedObject private var credits = CreditManager.shared

    var body: some View {
        ContentView()
            .ignoresSafeArea()
            .environmentObject(AuthManager.shared)
            .modelContainer(accounts.container)
            .id(accounts.owner)
            // Handle Supabase magic link deep link:
            // dumpster://auth/callback?token_hash=...&type=magiclink
            .onOpenURL { url in
                ReferralManager.shared.capture(url: url)
                if url.scheme == "dumpster", url.host == "auth" {
                    Task { await AuthManager.shared.handleCallback(url: url) }
                }
            }
            .sheet(isPresented: $credits.showOutOfCredits) { PaywallView().presentationDetents([.large]) }
            .alert("Local data was reset", isPresented: $accounts.recoveryNotice) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your on-device library couldn't be opened after an update. If you're signed in, your synced data will come back from your account.")
            }
            // Seed default captions for each account's store (deterministic IDs, no duplicates)
            .task(id: accounts.owner) {
                AIProfileSync.shared.seedIfNeeded(context: accounts.container.mainContext)
            }
            // Dashboard DAU: once per launch when already signed in
            // (fresh sign-ins fire from AuthManager.completeSignIn instead).
            .task { if AuthManager.shared.isSignedIn { Analytics.track(.sessionStart) } }
    }
}
