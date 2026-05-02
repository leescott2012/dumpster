import SwiftUI

// MARK: - Paywall Sheet

/// Shown when the user runs out of credits or taps the credit badge.
struct PaywallView: View {
    @ObservedObject private var credits = CreditManager.shared
    @Environment(\.dismiss) private var dismiss

    private let gold = Color(red: 200/255, green: 169/255, blue: 110/255)
    private let bg   = Color(white: 0.08)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Handle ──
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 40, height: 5)
                    .padding(.top, 14)
                    .padding(.bottom, 28)

                // ── Header ──
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(gold.opacity(0.12))
                            .frame(width: 72, height: 72)
                        Text("✦")
                            .font(.system(size: 32))
                            .foregroundColor(gold)
                    }

                    Text("AI Credits")
                        .font(.system(size: 28, weight: .black))
                        .foregroundColor(.white)

                    Text("Power your AI captions, vibe checks,\nand photo analysis.")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .padding(.bottom, 32)

                // ── Current Balance ──
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(gold)
                    Text("\(credits.balance) credits remaining")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(gold)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(gold.opacity(0.10))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(gold.opacity(0.25), lineWidth: 1))
                .padding(.bottom, 32)

                // ── Packs ──
                VStack(spacing: 12) {
                    ForEach(CreditManager.CreditPack.all) { pack in
                        PackRow(pack: pack)
                    }
                }
                .padding(.horizontal, 20)

                // ── Error ──
                if let error = credits.purchaseError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                }

                Spacer()

                // ── Restore ──
                Button("Restore Purchases") {
                    Task { await credits.restorePurchases() }
                }
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.3))
                .padding(.bottom, 32)
            }
        }
    }
}

// MARK: - Pack Row

private struct PackRow: View {
    let pack: CreditManager.CreditPack
    @ObservedObject private var credits = CreditManager.shared
    @State private var isPressing = false

    private let gold = Color(red: 200/255, green: 169/255, blue: 110/255)
    private let isPopular: Bool

    init(pack: CreditManager.CreditPack) {
        self.pack = pack
        self.isPopular = pack.badge != nil
    }

    var body: some View {
        Button {
            Task { await credits.purchase(pack) }
        } label: {
            HStack(spacing: 0) {
                // Credits icon + amount
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(isPopular ? gold : .white)
                        Text("\(pack.credits) credits")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text("≈ \(pack.credits) AI actions")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                }

                Spacer()

                // Badge + price
                VStack(alignment: .trailing, spacing: 4) {
                    if let badge = pack.badge {
                        Text(badge)
                            .font(.system(size: 10, weight: .black))
                            .tracking(0.5)
                            .foregroundColor(gold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(gold.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    Text(pack.displayPrice)
                        .font(.system(size: 17, weight: .black))
                        .foregroundColor(isPopular ? gold : .white)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isPopular ? gold.opacity(0.08) : Color(white: 0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isPopular ? gold.opacity(0.35) : Color.white.opacity(0.08), lineWidth: 1)
            )
            .scaleEffect(isPressing ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(credits.isPurchasing)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(.easeInOut(duration: 0.1)) { isPressing = true } }
                .onEnded   { _ in withAnimation(.easeInOut(duration: 0.15)) { isPressing = false } }
        )
        .overlay {
            if credits.isPurchasing {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.4))
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: gold))
            }
        }
    }
}

// MARK: - Credit Badge (inline in header/Dynamic Island)

/// Small tappable badge showing current credit balance.
struct CreditBadge: View {
    @ObservedObject private var credits = CreditManager.shared
    @State private var showPaywall = false

    private let gold = Color(red: 200/255, green: 169/255, blue: 110/255)
    private var isLow: Bool { credits.balance <= 3 }

    var body: some View {
        Button { showPaywall = true } label: {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                Text("\(credits.balance)")
                    .font(.system(size: 11, weight: .black))
                    .monospacedDigit()
            }
            .foregroundColor(isLow ? .white : gold)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isLow ? Color.red.opacity(0.75) : gold.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke(isLow ? Color.red.opacity(0.9) : gold.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        // Success toast
        .onChange(of: credits.lastPurchaseSuccess) { pack in
            guard pack != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                credits.lastPurchaseSuccess = nil
            }
        }
    }
}
