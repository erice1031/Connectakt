import SwiftUI
import UniformTypeIdentifiers

// MARK: - Optimization Sheet
// Covers readyToOptimize → optimizing → readyToUpload states.

struct OptimizationSheet: View {
    @Bindable var coordinator: ImportCoordinator
    let transfer: (any DigitaktTransferProtocol)?
    let destinationFolder: String

    var body: some View {
        VStack(spacing: 0) {
            // Header
            CKHeaderBar(title: sheetTitle, status: .disconnected)

            ScrollView {
                VStack(spacing: ConnektaktTheme.paddingLG) {
                    switch coordinator.phase {
                    case .readyToOptimize(let info):
                        FormatInfoPanel(info: info)
                        ConversionPlanPanel(info: info)
                        DestinationPanel(path: destinationFolder)
                        actionBar(info: info)

                    case .optimizing(let p):
                        optimizingPanel(progress: p)

                    case .readyToUpload(let result):
                        ResultPanel(result: result)
                        DestinationPanel(path: destinationFolder)
                        actionBar(result: result)

                    default:
                        EmptyView()
                    }
                }
                .padding(ConnektaktTheme.paddingMD)
            }
        }
        .background(ConnektaktTheme.background)
        .presentationDetents([.medium, .large])
        .presentationBackground(ConnektaktTheme.background)
    }

    private var sheetTitle: String {
        switch coordinator.phase {
        case .readyToOptimize:  return "IMPORT SAMPLE"
        case .optimizing:       return "OPTIMIZING..."
        case .readyToUpload:    return "READY TO UPLOAD"
        default:                return "IMPORT"
        }
    }

    @ViewBuilder
    private func actionBar(info: AudioFormatInfo) -> some View {
        HStack {
            CKButton("CANCEL", variant: .ghost) { coordinator.dismiss() }
            Spacer()
            CKButton(
                info.isAlreadyDigitaktSpec ? "UPLOAD AS-IS" : "OPTIMIZE + UPLOAD",
                icon: "waveform.badge.magnifyingglass",
                variant: .primary
            ) {
                coordinator.beginOptimization()
            }
        }
    }

    @ViewBuilder
    private func actionBar(result: OptimizationResult) -> some View {
        HStack {
            CKButton("CANCEL", variant: .ghost) { coordinator.dismiss() }
            Spacer()
            CKButton("UPLOAD TO DIGITAKT", icon: "arrow.up.circle.fill", variant: .primary) {
                coordinator.beginUpload(using: transfer, destinationFolder: destinationFolder)
            }
        }
    }

    @ViewBuilder
    private func optimizingPanel(progress: Double) -> some View {
        VStack(spacing: ConnektaktTheme.paddingXL) {
            Spacer(minLength: 20)

            Text("CONVERTING TO DIGITAKT SPEC")
                .font(ConnektaktTheme.titleFont)
                .foregroundStyle(ConnektaktTheme.textPrimary)
                .tracking(2)

            CKProgressBar(progress: progress)

            Text(String(format: "%.0f%%", progress * 100))
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundStyle(ConnektaktTheme.primary)
                .monospacedDigit()

            Text("16-BIT / 44.1KHZ / MONO")
                .font(ConnektaktTheme.smallFont)
                .foregroundStyle(ConnektaktTheme.textMuted)
                .tracking(2)

            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Format Info Panel

private struct FormatInfoPanel: View {
    let info: AudioFormatInfo

    var body: some View {
        VStack(spacing: 0) {
            sectionHeader("INPUT FILE")

            infoRow("FILENAME",    info.fileName + "." + info.fileExtension)
            infoRow("FORMAT",      info.formatDisplayName)
            infoRow("SAMPLE RATE", info.sampleRateString)
            infoRow("CHANNELS",    info.channelString)
            infoRow("BIT DEPTH",   info.bitDepthString)
            infoRow("DURATION",    info.durationString)
            infoRow("SIZE",        byteString(info.fileSizeBytes))
        }
        .ckPanel()
    }
}

// MARK: - Conversion Plan Panel

private struct ConversionPlanPanel: View {
    let info: AudioFormatInfo

    var body: some View {
        VStack(spacing: 0) {
            sectionHeader("OPTIMIZATION")

            if info.isAlreadyDigitaktSpec {
                HStack {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(ConnektaktTheme.waveformGreen)
                    Text("ALREADY DIGITAKT SPEC — NO CONVERSION NEEDED")
                        .font(ConnektaktTheme.smallFont)
                        .foregroundStyle(ConnektaktTheme.waveformGreen)
                        .tracking(1)
                    Spacer()
                }
                .padding(ConnektaktTheme.paddingMD)
            } else {
                ForEach(info.conversionSteps, id: \.label) { step in
                    conversionRow(step)
                }
                estimatedSizeRow(info: info)
            }
        }
        .ckPanel()
    }

    @ViewBuilder
    private func conversionRow(_ step: ConversionStep) -> some View {
        HStack {
            Text(step.label)
                .font(ConnektaktTheme.bodyFont)
                .foregroundStyle(ConnektaktTheme.textSecondary)
                .tracking(1)
                .frame(width: 100, alignment: .leading)

            Text(step.from)
                .font(ConnektaktTheme.bodyFont)
                .foregroundStyle(ConnektaktTheme.accent)
                .tracking(1)

            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundStyle(ConnektaktTheme.textMuted)

            Text(step.to)
                .font(ConnektaktTheme.bodyFont)
                .foregroundStyle(ConnektaktTheme.waveformGreen)
                .tracking(1)

            Spacer()

            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(ConnektaktTheme.waveformGreen)
        }
        .padding(.horizontal, ConnektaktTheme.paddingMD)
        .padding(.vertical, 10)
        .overlay(Rectangle().fill(ConnektaktTheme.primary.opacity(0.1)).frame(height: 1), alignment: .bottom)
    }

    @ViewBuilder
    private func estimatedSizeRow(info: AudioFormatInfo) -> some View {
        HStack {
            Text("EST. OUTPUT")
                .font(ConnektaktTheme.bodyFont)
                .foregroundStyle(ConnektaktTheme.textSecondary)
                .tracking(1)
            Spacer()
            Text(byteString(info.estimatedOutputSizeBytes))
                .font(ConnektaktTheme.bodyFont)
                .foregroundStyle(ConnektaktTheme.textPrimary)
                .tracking(1)
        }
        .padding(.horizontal, ConnektaktTheme.paddingMD)
        .padding(.vertical, 10)
    }
}

// MARK: - Result Panel

private struct ResultPanel: View {
    let result: OptimizationResult

    var body: some View {
        VStack(spacing: 0) {
            sectionHeader("OPTIMIZATION COMPLETE")

            VStack(spacing: ConnektaktTheme.paddingSM) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(ConnektaktTheme.waveformGreen)

                Text(result.outputURL.lastPathComponent)
                    .font(ConnektaktTheme.bodyFont)
                    .foregroundStyle(ConnektaktTheme.textPrimary)
                    .tracking(1)
            }
            .padding(ConnektaktTheme.paddingLG)

            ForEach(result.stepsApplied, id: \.self) { step in
                HStack {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(ConnektaktTheme.waveformGreen)
                    Text(step)
                        .font(ConnektaktTheme.smallFont)
                        .foregroundStyle(ConnektaktTheme.textSecondary)
                        .tracking(1)
                    Spacer()
                }
                .padding(.horizontal, ConnektaktTheme.paddingMD)
                .padding(.vertical, 6)
            }

            infoRow("OUTPUT SIZE",       result.outputSizeString)
            infoRow("CONVERSION TIME",   String(format: "%.2f SEC", result.conversionDurationSeconds))
        }
        .ckPanel()
    }
}

// MARK: - Destination Panel

private struct DestinationPanel: View {
    let path: String

    var body: some View {
        VStack(spacing: 0) {
            sectionHeader("UPLOAD DESTINATION")
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(ConnektaktTheme.primary)
                Text(path == "/" ? "/ (ROOT)" : path.uppercased())
                    .font(ConnektaktTheme.bodyFont)
                    .foregroundStyle(ConnektaktTheme.textPrimary)
                    .tracking(1)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("DIGITAKT")
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textMuted)
                    .tracking(1)
            }
            .padding(.horizontal, ConnektaktTheme.paddingMD)
            .padding(.vertical, 10)
        }
        .ckPanel()
    }
}

// MARK: - Progress Bar

struct CKProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(ConnektaktTheme.surfaceHigh)
                    .frame(height: 8)

                RoundedRectangle(cornerRadius: 2)
                    .fill(ConnektaktTheme.primary)
                    .frame(width: geo.size.width * CGFloat(min(progress, 1.0)), height: 8)
                    .animation(.linear(duration: 0.1), value: progress)
            }
        }
        .frame(height: 8)
    }
}

// MARK: - Shared Helpers (file-private)

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

@ViewBuilder
private func infoRow(_ label: String, _ value: String) -> some View {
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

private func byteString(_ bytes: Int64) -> String {
    let mb = Double(bytes) / 1_048_576
    return mb < 1 ? String(format: "%.0f KB", mb * 1024) : String(format: "%.1f MB", mb)
}
