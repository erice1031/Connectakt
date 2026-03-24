import SwiftUI

struct SettingsView: View {
    @Environment(ConnectionManager.self) private var connection
    @State private var autoConnect = true
    @State private var sampleRate: SampleRate = .khz44
    @State private var bitDepth: BitDepth = .bit16
    @State private var channelMode: ChannelMode = .mono

    enum SampleRate: String, CaseIterable {
        case khz44 = "44.1 KHZ"
        case khz48 = "48.0 KHZ"
    }

    enum BitDepth: String, CaseIterable {
        case bit16 = "16-BIT"
        case bit24 = "24-BIT"
    }

    enum ChannelMode: String, CaseIterable {
        case mono = "MONO"
        case stereo = "STEREO"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                CKHeaderBar(title: "SETTINGS", status: connection.status)

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
                    pickerRow(label: "SAMPLE RATE", selection: $sampleRate)
                    pickerRow(label: "BIT DEPTH", selection: $bitDepth)
                    pickerRow(label: "CHANNELS", selection: $channelMode)
                    infoRow(label: "TARGET FORMAT", value: "WAV PCM")
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
                }
            }
        }
        .ckScreen()
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
    private func pickerRow<T: RawRepresentable & CaseIterable & Hashable>(
        label: String,
        selection: Binding<T>
    ) -> some View where T.RawValue == String, T.AllCases: RandomAccessCollection {
        HStack {
            Text(label)
                .font(ConnektaktTheme.bodyFont)
                .foregroundStyle(ConnektaktTheme.textSecondary)
                .tracking(1)
            Spacer()
            Picker("", selection: selection) {
                ForEach(Array(T.allCases), id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.menu)
            .tint(ConnektaktTheme.primary)
            .font(ConnektaktTheme.bodyFont)
        }
        .padding(.horizontal, ConnektaktTheme.paddingMD)
        .padding(.vertical, 6)
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
}
