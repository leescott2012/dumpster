import SwiftUI
import StoreKit

// MARK: - Paywall Sheet

/// Hybrid paywall: DUMPSTER Pro subscription on top, one-time credit packs below.
struct PaywallView: View {
    @ObservedObject private var credits = CreditManager.shared
    @ObservedObject private var sub     = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlan: SubscriptionManager.Plan = .all[2] // default to yearly

    private let gold = Color(red: 200/255, green: 169/255, blue: 110/255)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {

                    // Handle
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 40, height: 5)
                        .padding(.top, 10)
                        .padding(.bottom, 20)

                    header
                    if sub.isPro {
                        proActiveBadge.padding(.bottom, 24)
                    } else {
                        balancePill.padding(.bottom, 22)
                    }

                    // ── Subscription Plans ──
                    if !sub.isPro {
                        sectionLabel("DUMPSTER PRO", subtitle: "Unlimited AI · No credit limits")
                            .padding(.bottom, 12)
                        VStack(spacing: 10) {
                            ForEach(SubscriptionManager.Plan.all) { plan in
                                PlanRow(
                                    plan: plan,
                                    selected: selectedPlan.id == plan.id,
                                    price: sub.price(for: plan)
                                ) { selectedPlan = plan }
                            }
                        }
                        .padding(.horizontal, 20)

                        ctaButton
                            .padding(.horizontal, 20)
                            .padding(.top, 16)

                        Text("Auto-renews · Cancel anytime in Settings")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.top, 8)
                            .padding(.bottom, 28)
                    }

                    // ── One-time credit packs ──
                    sectionLabel(
                        "OR BUY CREDITS",
                        subtitle: "One-time. No subscription needed."
                    ).padding(.bottom, 12)

                    VStack(spacing: 10) {
                        ForEach(CreditManager.CreditPack.all) { pack in
                            PackRow(pack: pack)
                        }
                    }
                    .padding(.horizontal, 20)

                    if let error = sub.purchaseError ?? credits.purchaseError {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.red.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.top, 16)
                    }

                    // ── Footer ──
                    HStack(spacing: 18) {
                        Button("Restore") {
                            Task {
                                await sub.restorePurchases()
                                await credits.restorePurchases()
                            }
                        }
                        Link("Terms", destination: URL(string: "https://dumpster.app/terms")!)
                        Link("Privacy", destination: URL(string: "https://dumpster.app/privacy")!)
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.top, 28)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(gold.opacity(0.12)).frame(width: 72, height: 72)
                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(gold)
            }
            Text(sub.isPro ? "You're a Pro ✦" : "Unlock Everything")
                .font(.system(size: 26, weight: .black))
                .foregroundColor(.white)
            Text(sub.isPro
                 ? "Unlimited AI captions, vibe checks, and analysis."
                 : "AI captions, vibe checks, photo analysis,\nand auto-generate dumps.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .padding(.bottom, 20)
    }

    private var balancePill: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(gold)
            Text("\(credits.balance) credits remaining")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(gold)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(gold.opacity(0.10))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(gold.opacity(0.25), lineWidth: 1))
    }

    private var proActiveBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 13))
            Text("PRO ACTIVE")
                .font(.system(size: 11, weight: .black)).tracking(1.2)
        }
        .foregroundColor(.black)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(gold)
        .clipShape(Capsule())
    }

    private func sectionLabel(_ title: String, subtitle: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .black))
                .tracking(1.6)
                .foregroundColor(gold)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
        }
    }

    private var ctaButton: some View {
        Button {
            Task { await sub.purchase(selectedPlan) }
        } label: {
            HStack {
                if sub.isPurchasing {
                    ProgressView().tint(.black)
                } else {
                    Text("Start \(selectedPlan.title)")
                        .font(.system(size: 15, weight: .black))
                        .tracking(0.5)
                }
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(gold)
            .clipShape(Capsule())
            .shadow(color: gold.opacity(0.35), radius: 12, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(sub.isPurchasing)
    }
}

// MARK: - Plan Row

private struct PlanRow: View {
    let plan: SubscriptionManager.Plan
    let selected: Bool
    let price: String
    let onTap: () -> Void

    private let gold = Color(red: 200/255, green: 169/255, blue: 110/255)

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(selected ? gold : Color.white.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if selected {
                        Circle().fill(gold).frame(width: 12, height: 12)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(plan.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        if let badge = plan.badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .black))
                                .tracking(0.8)
                                .foregroundColor(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(gold)
                                .clipShape(Capsule())
                        }
                    }
                    if let s = plan.savings {
                        Text(s)
                            .font(.system(size: 11))
                            .foregroundColor(gold)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text(price)
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(.white)
                    Text(plan.perPeriod)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(selected ? gold.opacity(0.10) : Color(white: 0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? gold.opacity(0.5) : Color.white.opacity(0.07), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pack Row (one-time credits)

private struct PackRow: View {
    let pack: CreditManager.CreditPack
    @ObservedObject private var credits = CreditManager.shared

    private let gold = Color(red: 200/255, green: 169/255, blue: 110/255)
    private var isPopular: Bool { pack.badge != nil }

    var body: some View {
        Button {
            Task { await credits.purchase(pack) }
        } label: {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(isPopular ? gold : .white)
                        Text("\(pack.credits) credits")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text("≈ \(pack.credits) AI actions")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if let badge = pack.badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .black))
                            .tracking(0.5)
                            .foregroundColor(gold)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(gold.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    Text(pack.displayPrice)
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(isPopular ? gold : .white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isPopular ? gold.opacity(0.08) : Color(white: 0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isPopular ? gold.opacity(0.30) : Color.white.opacity(0.07), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(credits.isPurchasing)
        .overlay {
            if credits.isPurchasing {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.black.opacity(0.4))
                ProgressView().tint(gold)
            }
        }
    }
}

// MARK: - Credit Badge (inline in header/Dynamic Island)

/// Small tappable badge showing current credit balance — or a Pro mark if subscribed.
struct CreditBadge: View {
    @ObservedObject private var credits = CreditManager.shared
    @ObservedObject private var sub     = SubscriptionManager.shared
    @State private var showPaywall = false

    private let gold = Color(red: 200/255, green: 169/255, blue: 110/255)
    private var isLow: Bool { !sub.isPro && credits.balance <= 3 }

    var body: some View {
        Button { showPaywall = true } label: {
            HStack(spacing: 4) {
                Image(systemName: sub.isPro ? "checkmark.seal.fill" : "sparkles")
                    .font(.system(size: 10, weight: .bold))
                if sub.isPro {
                    Text("PRO")
                        .font(.system(size: 10, weight: .black)).tracking(0.6)
                } else {
                    Text("\(credits.balance)")
                        .font(.system(size: 11, weight: .black))
                        .monospacedDigit()
                }
            }
            .foregroundColor(isLow ? .white : gold)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(isLow ? Color.red.opacity(0.75) : gold.opacity(0.12))
            )
            .overlay(
                Capsule().stroke(isLow ? Color.red.opacity(0.9) : gold.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
    }
}
