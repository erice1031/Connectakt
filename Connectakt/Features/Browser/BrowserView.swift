import SwiftUI

struct BrowserView: View {
    @Environment(ConnectionManager.self) private var connection

    var body: some View {
        VStack(spacing: 0) {
            CKHeaderBar(title: "CONNECTAKT", status: connection.status)

            if connection.status.isConnected {
                SampleListView()
            } else {
                ConnectPromptView()
            }
        }
        .ckScreen()
    }
}

// MARK: - Connect Prompt

private struct ConnectPromptView: View {
    @Environment(ConnectionManager.self) private var connection
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                // USB icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(ConnektaktTheme.textMuted, lineWidth: 1.5)
                        .frame(width: 72, height: 72)

                    Image(systemName: "cable.connector")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(ConnektaktTheme.textSecondary)
                }
                .scaleEffect(pulseScale)
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                        pulseScale = 1.06
                    }
                }

                VStack(spacing: 6) {
                    Text("DIGITAKT NOT FOUND")
                        .font(ConnektaktTheme.largeFont)
                        .foregroundStyle(ConnektaktTheme.textPrimary)
                        .tracking(2)

                    Text("CONNECT YOUR DIGITAKT VIA USB CABLE")
                        .font(ConnektaktTheme.smallFont)
                        .foregroundStyle(ConnektaktTheme.textSecondary)
                        .tracking(1)

                    Text("REQUIRES USB-B → USB-C ADAPTER")
                        .font(ConnektaktTheme.smallFont)
                        .foregroundStyle(ConnektaktTheme.textMuted)
                        .tracking(1)
                }
                .multilineTextAlignment(.center)
            }

            Spacer()

            // Dev simulation button
            VStack(spacing: 8) {
                Divider()
                    .background(ConnektaktTheme.textMuted)
                    .padding(.horizontal)

                Text("DEVELOPMENT MODE")
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textMuted)
                    .tracking(1)

                CKButton("SIMULATE USB CONNECTION", icon: "cable.connector", variant: .secondary) {
                    connection.simulateConnect()
                }
                .padding(.bottom, ConnektaktTheme.paddingLG)
            }
        }
    }
}

// MARK: - Sample List

private struct SampleListView: View {
    @Environment(ConnectionManager.self) private var connection
    @State private var selectedSample: SampleFile?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("SAMPLES/")
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textSecondary)
                    .tracking(1)

                Text("\(connection.samples.count) FILES")
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textMuted)
                    .tracking(1)

                Spacer()

                CKButton("UPLOAD", icon: "arrow.up", variant: .primary) {}
                CKButton("IMPORT", icon: "arrow.down", variant: .secondary) {}
            }
            .padding(.horizontal, ConnektaktTheme.paddingMD)
            .padding(.vertical, ConnektaktTheme.paddingSM)
            .background(ConnektaktTheme.surface)

            Rectangle()
                .fill(ConnektaktTheme.primary.opacity(0.15))
                .frame(height: 1)

            // File list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(connection.samples) { sample in
                        SampleRow(sample: sample, isSelected: selectedSample?.id == sample.id)
                            .onTapGesture { selectedSample = sample }
                    }
                }
            }

            // Storage meter
            CKStorageMeter(
                usedMB: connection.usedStorageMB,
                totalMB: connection.totalStorageMB
            )
        }
    }
}

// MARK: - Sample Row

private struct SampleRow: View {
    let sample: SampleFile
    let isSelected: Bool

    var body: some View {
        HStack(spacing: ConnektaktTheme.paddingSM) {
            // Type indicator
            Image(systemName: sample.isFolder ? "folder" : "waveform")
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? ConnektaktTheme.background : ConnektaktTheme.textSecondary)
                .frame(width: 16)

            Text(sample.name)
                .font(ConnektaktTheme.bodyFont)
                .foregroundStyle(isSelected ? ConnektaktTheme.background : ConnektaktTheme.textPrimary)
                .lineLimit(1)

            Spacer()

            Text(sample.sizeString)
                .font(ConnektaktTheme.smallFont)
                .foregroundStyle(isSelected ? ConnektaktTheme.background.opacity(0.7) : ConnektaktTheme.textSecondary)
                .monospacedDigit()

            Image(systemName: "chevron.right")
                .font(.system(size: 9))
                .foregroundStyle(isSelected ? ConnektaktTheme.background.opacity(0.5) : ConnektaktTheme.textMuted)
        }
        .padding(.horizontal, ConnektaktTheme.paddingMD)
        .padding(.vertical, 10)
        .background(isSelected ? ConnektaktTheme.primary : Color.clear)
        .overlay(
            Rectangle()
                .fill(ConnektaktTheme.primary.opacity(0.1))
                .frame(height: 1),
            alignment: .bottom
        )
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.1), value: isSelected)
    }
}

#Preview {
    BrowserView()
        .environment(ConnectionManager())
}
