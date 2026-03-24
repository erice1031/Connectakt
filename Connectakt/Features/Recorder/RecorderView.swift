import SwiftUI

struct RecorderView: View {
    @Environment(ConnectionManager.self) private var connection
    @State private var recorderState: RecorderState = .idle
    @State private var elapsed: TimeInterval = 0
    @State private var timer: Timer?

    enum RecorderState { case idle, recording, stopped }

    var body: some View {
        VStack(spacing: 0) {
            CKHeaderBar(title: "RECORD", status: connection.status)

            // Info strip
            HStack {
                infoCell(label: "INPUT", value: connection.status.isConnected ? "DIGITAKT USB" : "NO DEVICE")
                Divider().background(ConnektaktTheme.textMuted).frame(height: 20)
                infoCell(label: "FORMAT", value: "16-BIT / 48KHZ / MONO")
                Divider().background(ConnektaktTheme.textMuted).frame(height: 20)
                infoCell(label: "STATUS", value: recorderState.label, color: recorderState.color)
            }
            .padding(.horizontal, ConnektaktTheme.paddingMD)
            .padding(.vertical, ConnektaktTheme.paddingSM)
            .background(ConnektaktTheme.surface)

            Rectangle()
                .fill(ConnektaktTheme.primary.opacity(0.15))
                .frame(height: 1)

            Spacer()

            // Waveform
            VStack(spacing: ConnektaktTheme.paddingSM) {
                CKWaveformView(
                    isActive: recorderState == .recording,
                    color: recorderState == .recording ? ConnektaktTheme.danger : ConnektaktTheme.waveformGreen
                )
                .frame(height: 80)
                .padding(.horizontal, ConnektaktTheme.paddingLG)
                .ckPanel()
                .padding(.horizontal, ConnektaktTheme.paddingLG)

                // Timecode
                Text(formattedTime(elapsed))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(recorderState == .recording ? ConnektaktTheme.danger : ConnektaktTheme.textPrimary)
                    .monospacedDigit()
            }

            Spacer()

            // Transport
            VStack(spacing: ConnektaktTheme.paddingMD) {
                // Big record button
                Button(action: toggleRecord) {
                    ZStack {
                        Circle()
                            .strokeBorder(ConnektaktTheme.danger.opacity(0.5), lineWidth: 2)
                            .frame(width: 72, height: 72)

                        Circle()
                            .fill(ConnektaktTheme.danger)
                            .frame(width: recorderState == .recording ? 28 : 52)
                            .animation(.easeInOut(duration: 0.15), value: recorderState == .recording)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!connection.status.isConnected)
                .opacity(connection.status.isConnected ? 1.0 : 0.35)

                Text(recorderState == .recording ? "TAP TO STOP" : "TAP TO RECORD")
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textSecondary)
                    .tracking(2)

                // Secondary actions
                HStack(spacing: ConnektaktTheme.paddingMD) {
                    CKButton("PLAY", icon: "play.fill", variant: .secondary) {}
                        .disabled(recorderState != .stopped)
                        .opacity(recorderState == .stopped ? 1.0 : 0.35)

                    CKButton("DISCARD", icon: "trash", variant: .ghost) {
                        recorderState = .idle
                        elapsed = 0
                        timer?.invalidate()
                    }
                    .disabled(recorderState == .idle)
                    .opacity(recorderState != .idle ? 1.0 : 0.35)

                    CKButton("OPTIMIZE + UPLOAD", icon: "arrow.up.circle", variant: .primary) {}
                        .disabled(recorderState != .stopped)
                        .opacity(recorderState == .stopped ? 1.0 : 0.35)
                }
            }
            .padding(.bottom, ConnektaktTheme.paddingXL)
        }
        .ckScreen()
    }

    // MARK: - Helpers

    private func toggleRecord() {
        switch recorderState {
        case .idle:
            recorderState = .recording
            elapsed = 0
            timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { _ in
                elapsed += 0.01
            }
        case .recording:
            recorderState = .stopped
            timer?.invalidate()
        case .stopped:
            recorderState = .idle
            elapsed = 0
        }
    }

    private func formattedTime(_ t: TimeInterval) -> String {
        let minutes = Int(t) / 60
        let seconds = Int(t) % 60
        let hundredths = Int((t.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, hundredths)
    }

    @ViewBuilder
    private func infoCell(label: String, value: String, color: Color = ConnektaktTheme.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(ConnektaktTheme.smallFont)
                .foregroundStyle(ConnektaktTheme.textMuted)
                .tracking(1)
            Text(value)
                .font(ConnektaktTheme.smallFont)
                .foregroundStyle(color)
                .tracking(1)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension RecorderView.RecorderState {
    var label: String {
        switch self {
        case .idle:      return "READY"
        case .recording: return "● REC"
        case .stopped:   return "STOPPED"
        }
    }

    var color: Color {
        switch self {
        case .idle:      return ConnektaktTheme.textSecondary
        case .recording: return ConnektaktTheme.danger
        case .stopped:   return ConnektaktTheme.accent
        }
    }
}

#Preview {
    RecorderView()
        .environment(ConnectionManager())
}
