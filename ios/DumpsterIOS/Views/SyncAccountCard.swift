import SwiftUI
import SwiftData

// MARK: - Sync Account Card
//
// Displayed in the AI Settings tab.
// Shows sign-in state and provides magic link auth flow.
// When signed in, triggers an immediate AI profile sync.

struct SyncAccountCard: View {
    @EnvironmentObject private var auth: AuthManager
    @Environment(\.modelContext) private var modelContext
    @State private var showSignIn = false
    @State private var isSyncing = false
    @State private var lastSynced: Date?

    private let gold = Color(hex: "#C8A96E")

    var body: some View {
        Group {
            if auth.isSignedIn {
                signedInView
            } else {
                signedOutView
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .sheet(isPresented: $showSignIn) {
            SignInView()
                .presentationDetents([.large])
        }
    }

    // MARK: - Signed in

    private var signedInView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "checkmark.icloud.fill")
                    .foregroundColor(gold)
                Text("Synced to Cloud")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: syncNow) {
                    if isSyncing {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .disabled(isSyncing)
            }

            Text(auth.userEmail ?? "")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))

            if let t = lastSynced {
                Text("Last synced \(t.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.3))
            }

            Divider().background(Color.white.opacity(0.1))

            Button(action: signOut) {
                Text("Sign Out")
                    .font(.system(size: 12))
                    .foregroundColor(.red.opacity(0.7))
            }
        }
    }

    // MARK: - Signed out

    private var signedOutView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "icloud.slash")
                    .foregroundColor(.white.opacity(0.35))
                Text("Not signed in")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
            }
            Text("Sign in to sync your taste profile, AI rules, and caption pool across your iPhone, iPad, and web.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.35))
                .lineSpacing(3)
            Button {
                showSignIn = true
            } label: {
                Text("Sign In with Email →")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(gold)
            }
        }
    }

    // MARK: - Actions

    private func syncNow() {
        guard let userId = auth.userId, let jwt = auth.jwt else { return }
        isSyncing = true
        Task {
            await AIProfileSync.shared.syncOnSignIn(userId: userId, jwt: jwt,
                                                     context: modelContext)
            await MainActor.run {
                isSyncing = false
                lastSynced = Date()
            }
        }
    }

    private func signOut() {
        Task { await auth.signOut() }
    }
}
