import SwiftUI
import StoreKit

// MARK: - PaywallView
//
// Modal sheet shown when a free user taps a Pro-gated feature.
// Present with .sheet(isPresented: ...) { PaywallView() }

struct PaywallView: View {
    @Environment(StoreManager.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            CKHeaderBar(title: "CONNECTAKT PRO", status: .disconnected)

            ScrollView {
                VStack(spacing: ConnektaktTheme.paddingLG) {
                    heroSection
                    featureList
                    pricingSection
                    actionButtons
                    legalNote
                }
                .padding(ConnektaktTheme.paddingMD)
            }
        }
        .background(ConnektaktTheme.background)
        .presentationDetents([.large])
        .presentationBackground(ConnektaktTheme.background)
        .alert("ERROR", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
                .font(ConnektaktTheme.bodyFont)
        }
    }

    // MARK: - Sections

    private var heroSection: some View {
        VStack(spacing: ConnektaktTheme.paddingSM) {
            Image(systemName: "waveform.badge.plus")
                .font(.system(size: 52))
                .foregroundStyle(ConnektaktTheme.primary)
                .padding(.top, ConnektaktTheme.paddingLG)

            Text("UPGRADE TO PRO")
                .font(.system(.title2, design: .monospaced).bold())
                .foregroundStyle(ConnektaktTheme.textPrimary)
                .tracking(3)

            Text("UNLOCK THE FULL CONNECTAKT EXPERIENCE")
                .font(ConnektaktTheme.smallFont)
                .foregroundStyle(ConnektaktTheme.textMuted)
                .tracking(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, ConnektaktTheme.paddingSM)
    }

    private var featureList: some View {
        VStack(spacing: 0) {
            sectionHeader("INCLUDED IN PRO")
            featureRow("waveform.circle.fill",    "SAMPLE EDITOR",     "Trim, normalize, pitch, time-stretch")
            featureRow("square.stack.fill",        "BATCH OPERATIONS",  "Select + transfer multiple files at once")
            featureRow("record.circle.fill",       "AUDIO RECORDING",   "Capture Digitakt output via USB")
            featureRow("slider.horizontal.3",      "AUV3 PLUGIN CHAIN", "Process samples through third-party effects")
            featureRow("arrow.triangle.2.circlepath", "iCLOUD BACKUP", "Back up projects to iCloud")
        }
        .ckPanel()
    }

    private var pricingSection: some View {
        VStack(spacing: 0) {
            sectionHeader("PRICING")
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CONNECTAKT PRO")
                        .font(ConnektaktTheme.bodyFont)
                        .foregroundStyle(ConnektaktTheme.textPrimary)
                        .tracking(1)
                    Text("ONE-TIME PURCHASE · FAMILY SHARING")
                        .font(ConnektaktTheme.smallFont)
                        .foregroundStyle(ConnektaktTheme.textMuted)
                        .tracking(1)
                }
                Spacer()
                Text(store.proProduct?.displayPrice ?? "$7.99")
                    .font(.system(.title3, design: .monospaced).bold())
                    .foregroundStyle(ConnektaktTheme.primary)
            }
            .padding(.horizontal, ConnektaktTheme.paddingMD)
            .padding(.vertical, 14)
        }
        .ckPanel()
    }

    private var actionButtons: some View {
        VStack(spacing: ConnektaktTheme.paddingSM) {
            CKButton(
                store.isLoading ? "PROCESSING..." : "UNLOCK PRO  —  \(store.proProduct?.displayPrice ?? "$7.99")",
                icon: store.isLoading ? nil : "lock.open.fill",
                variant: .primary
            ) {
                Task { await store.purchase() }
            }
            .disabled(store.isLoading || store.proProduct == nil)

            HStack(spacing: ConnektaktTheme.paddingMD) {
                CKButton("RESTORE PURCHASES", variant: .ghost) {
                    Task { await store.restore() }
                }
                .disabled(store.isLoading)

                CKButton("NOT NOW", variant: .ghost) {
                    dismiss()
                }
            }
        }
    }

    private var legalNote: some View {
        Text("Payment will be charged to your Apple ID account at confirmation of purchase. No subscription — one-time purchase only.")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(ConnektaktTheme.textMuted)
            .multilineTextAlignment(.center)
            .padding(.bottom, ConnektaktTheme.paddingLG)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func featureRow(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(ConnektaktTheme.waveformGreen)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ConnektaktTheme.bodyFont)
                    .foregroundStyle(ConnektaktTheme.textPrimary)
                    .tracking(1)
                Text(subtitle)
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textMuted)
                    .tracking(1)
            }

            Spacer()

            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(ConnektaktTheme.waveformGreen)
        }
        .padding(.horizontal, ConnektaktTheme.paddingMD)
        .padding(.vertical, 10)
        .overlay(Rectangle().fill(ConnektaktTheme.primary.opacity(0.08)).frame(height: 1), alignment: .bottom)
    }

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(ConnektaktTheme.smallFont)
                .foregroundStyle(ConnektaktTheme.textSecondary)
                .tracking(2)
            Spacer()
        }
        .padding(.horizontal, ConnektaktTheme.paddingMD)
        .padding(.top, ConnektaktTheme.paddingSM)
        .padding(.bottom, ConnektaktTheme.paddingXS)
        .background(ConnektaktTheme.surfaceHigh)
    }
}

// MARK: - Pro Gate Modifier
//
// Usage: someView.proGated(store: store, feature: "BATCH OPS")
//   → Overlay a paywall trigger on the view if not Pro.

extension View {
    /// Disables the view and shows a paywall sheet when tapped if not Pro.
    func proGated(isPro: Bool, showingPaywall: Binding<Bool>) -> some View {
        modifier(ProGateModifier(isPro: isPro, showingPaywall: showingPaywall))
    }
}

private struct ProGateModifier: ViewModifier {
    let isPro: Bool
    @Binding var showingPaywall: Bool

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
    }
}
