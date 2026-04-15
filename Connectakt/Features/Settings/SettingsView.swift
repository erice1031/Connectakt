import SwiftUI

struct SettingsView: View {
    @Environment(ConnectionManager.self) private var connection
    @Environment(StoreManager.self)      private var store
    @State private var autoConnect = true
    @State private var showDiagnostics = false
    @State private var showPaywall = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                CKHeaderBar(title: "SETTINGS", status: connection.status)

                // Pro upgrade banner (only shown to free users)
                if !store.isPro {
                    proUpgradeBanner
                }

                settingSection("CONNECTION") {
                    toggleRow(label: "AUTO-CONNECT", value: $autoConnect)
                    infoRow(label: "PROTOCOL", value: "ELEKTRON TRANSFER")
                    infoRow(label: "USB VID", value: "0x1935 (ELEKTRON)")
                    infoRow(label: "DEVICE", value: connection.status.isConnected ? "DIGITAKT" : "NOT FOUND")

                    if connection.status.isConnected {
                        buttonRow {
                            CKButton("DISCONNECT", icon: "cable.connector.slash", variant: .danger) {
                                connection.disconnect()
                            }
                        }
                    } else {
                        buttonRow {
                            CKButton("SIMULATE CONNECT", icon: "cable.connector", variant: .secondary) {
                                connection.simulateConnect()
                            }
                        }
                    }
                }

                settingSection("SAMPLE OPTIMIZER") {
                    infoRow(label: "FORMAT",      value: "WAV PCM")
                    infoRow(label: "SAMPLE RATE", value: "44.1 KHZ")
                    infoRow(label: "BIT DEPTH",   value: "16-BIT")
                    infoRow(label: "CHANNELS",    value: "MONO")
                    infoRow(label: "NOTE",        value: "DIGITAKT SPEC (FIXED)")
                }

                settingSection("PURCHASE") {
                    infoRow(label: "STATUS", value: store.isPro ? "PRO ✓" : "FREE")
                    if store.isPro {
                        infoRow(label: "FEATURES", value: "ALL UNLOCKED")
                    } else {
                        buttonRow {
                            CKButton("UPGRADE TO PRO", icon: "lock.open.fill", variant: .primary) {
                                showPaywall = true
                            }
                        }
                        buttonRow {
                            CKButton("RESTORE PURCHASES", variant: .ghost) {
                                Task { await store.restore() }
                            }
                        }
                    }
                }

                settingSection("ABOUT") {
                    infoRow(label: "APP", value: "CONNECTAKT")
                    infoRow(label: "VERSION", value: "1.0.0 (1)")
                    infoRow(label: "PLATFORM", value: platformString)
                    infoRow(label: "TARGET", value: "ELEKTRON DIGITAKT")
                    infoRow(label: "BUILT WITH", value: "SWIFTUI + AVFOUNDATION")
                }

                settingSection("DEVELOPER") {
                    infoRow(label: "GITHUB", value: "erice1031/Connectakt")
                    infoRow(label: "AGENT DOCS", value: "ROADMAP.md / CODEX.md")
                    buttonRow {
                        CKButton("MIDI DIAGNOSTICS", icon: "waveform.path", variant: .secondary) {
                            showDiagnostics = true
                        }
                    }
                }
            }
        }
        .ckScreen()
        .sheet(isPresented: $showDiagnostics) {
            MIDIDiagnosticsView()
                .environment(connection)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environment(store)
        }
    }

    // MARK: - Pro Banner

    private var proUpgradeBanner: some View {
        Button { showPaywall = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(ConnektaktTheme.background)
                VStack(alignment: .leading, spacing: 2) {
                    Text("UNLOCK CONNECTAKT PRO")
                        .font(ConnektaktTheme.bodyFont)
                        .foregroundStyle(ConnektaktTheme.background)
                        .tracking(1)
                    Text("EDITOR · BATCH OPS · RECORDING · AUV3")
                        .font(ConnektaktTheme.smallFont)
                        .foregroundStyle(ConnektaktTheme.background.opacity(0.7))
                        .tracking(1)
                }
                Spacer()
                Text(store.proProduct?.displayPrice ?? "$7.99")
                    .font(.system(.callout, design: .monospaced).bold())
                    .foregroundStyle(ConnektaktTheme.background)
            }
            .padding(.horizontal, ConnektaktTheme.paddingMD)
            .padding(.vertical, 12)
            .background(ConnektaktTheme.primary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, ConnektaktTheme.paddingSM)
            .padding(.top, ConnektaktTheme.paddingMD)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section Builder

    @ViewBuilder
    private func settingSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textSecondary)
                    .tracking(2)
                Spacer()
            }
            .padding(.horizontal, ConnektaktTheme.paddingMD)
            .padding(.top, ConnektaktTheme.paddingMD)
            .padding(.bottom, ConnektaktTheme.paddingXS)

            VStack(spacing: 0) {
                content()
            }
            .ckPanel()
            .padding(.horizontal, ConnektaktTheme.paddingSM)
            .padding(.bottom, ConnektaktTheme.paddingSM)
        }
    }

    @ViewBuilder
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(ConnektaktTheme.bodyFont)
                .foregroundStyle(ConnektaktTheme.textSecondary)
                .tracking(1)
            Spacer()
            Text(value)
                .font(ConnektaktTheme.bodyFont)
                .foregroundStyle(ConnektaktTheme.textPrimary)
                .tracking(1)
        }
        .padding(.horizontal, ConnektaktTheme.paddingMD)
        .padding(.vertical, 10)
        .overlay(Rectangle().fill(ConnektaktTheme.primary.opacity(0.1)).frame(height: 1), alignment: .bottom)
    }

    @ViewBuilder
    private func toggleRow(label: String, value: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(ConnektaktTheme.bodyFont)
                .foregroundStyle(ConnektaktTheme.textSecondary)
                .tracking(1)
            Spacer()
            Toggle("", isOn: value)
                .tint(ConnektaktTheme.primary)
                .labelsHidden()
        }
        .padding(.horizontal, ConnektaktTheme.paddingMD)
        .padding(.vertical, 8)
        .overlay(Rectangle().fill(ConnektaktTheme.primary.opacity(0.1)).frame(height: 1), alignment: .bottom)
    }

    @ViewBuilder
    private func buttonRow(@ViewBuilder content: () -> some View) -> some View {
        HStack {
            Spacer()
            content()
        }
        .padding(.horizontal, ConnektaktTheme.paddingMD)
        .padding(.vertical, ConnektaktTheme.paddingSM)
    }

    private var platformString: String {
        #if os(iOS)
        return "iPHONE / iPAD"
        #elseif os(macOS)
        return "macOS"
        #else
        return "UNKNOWN"
        #endif
    }
}

#Preview {
    SettingsView()
        .environment(ConnectionManager())
        .environment(StoreManager())
}
