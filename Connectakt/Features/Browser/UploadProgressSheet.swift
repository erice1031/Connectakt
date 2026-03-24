import SwiftUI

// MARK: - Upload Progress Sheet
// Covers uploading → done states.

struct UploadProgressSheet: View {
    @Bindable var coordinator: ImportCoordinator

    var body: some View {
        VStack(spacing: 0) {
            CKHeaderBar(title: headerTitle, status: .connected(deviceName: "DIGITAKT"))

            VStack(spacing: ConnektaktTheme.paddingXL) {
                Spacer(minLength: 20)

                switch coordinator.phase {
                case .uploading(let p):
                    uploadingContent(progress: p)
                case .done(let filename):
                    doneContent(filename: filename)
                default:
                    EmptyView()
                }

                Spacer(minLength: 20)
            }
            .padding(ConnektaktTheme.paddingLG)
        }
        .background(ConnektaktTheme.background)
        .presentationDetents([.medium])
        .presentationBackground(ConnektaktTheme.background)
    }

    private var headerTitle: String {
        if case .done = coordinator.phase { return "UPLOAD COMPLETE" }
        return "UPLOADING..."
    }

    @ViewBuilder
    private func uploadingContent(progress: Double) -> some View {
        VStack(spacing: ConnektaktTheme.paddingLG) {
            // Animated transfer indicator
            HStack(spacing: 4) {
                ForEach(0..<8, id: \.self) { i in
                    TransferDot(isActive: progress > Double(i) / 8.0)
                }
            }

            Text("SENDING TO DIGITAKT")
                .font(ConnektaktTheme.titleFont)
                .foregroundStyle(ConnektaktTheme.textPrimary)
                .tracking(2)

            CKProgressBar(progress: progress)

            Text(String(format: "%.0f%%", progress * 100))
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundStyle(ConnektaktTheme.primary)
                .monospacedDigit()

            Text("DO NOT DISCONNECT CABLE")
                .font(ConnektaktTheme.smallFont)
                .foregroundStyle(ConnektaktTheme.textMuted)
                .tracking(2)
        }
    }

    @ViewBuilder
    private func doneContent(filename: String) -> some View {
        VStack(spacing: ConnektaktTheme.paddingLG) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(ConnektaktTheme.waveformGreen)

            VStack(spacing: ConnektaktTheme.paddingXS) {
                Text("UPLOADED SUCCESSFULLY")
                    .font(ConnektaktTheme.largeFont)
                    .foregroundStyle(ConnektaktTheme.waveformGreen)
                    .tracking(2)

                Text(filename)
                    .font(ConnektaktTheme.bodyFont)
                    .foregroundStyle(ConnektaktTheme.textSecondary)
                    .tracking(1)
            }

            CKButton("DONE", icon: "checkmark", variant: .primary) {
                coordinator.dismiss()
            }
        }
    }
}

// MARK: - Transfer Dot (indicator animation)

private struct TransferDot: View {
    let isActive: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(isActive ? ConnektaktTheme.primary : ConnektaktTheme.surfaceHigh)
            .frame(width: 18, height: 10)
            .animation(.easeInOut(duration: 0.2), value: isActive)
    }
}
