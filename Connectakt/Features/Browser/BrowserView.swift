import SwiftUI
import UniformTypeIdentifiers

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
    @State private var importer = ImportCoordinator()
    @State private var downloader = DownloadCoordinator()
    @State private var pathStack: [String] = ["/"]

    private var currentPath: String { pathStack.last ?? "/" }

    private func navigate(into folder: SampleFile) {
        guard folder.isFolder else { return }
        let next = currentPath == "/" ? "/\(folder.name)" : "\(currentPath)/\(folder.name)"
        pathStack.append(next)
        Task { await connection.refreshSamples(path: next) }
    }

    private func navigateUp() {
        guard pathStack.count > 1 else { return }
        pathStack.removeLast()
        Task { await connection.refreshSamples(path: currentPath) }
    }

    private func startDownload(_ sample: SampleFile) {
        guard let transfer = connection.transfer else { return }
        let remotePath = currentPath == "/" ? "/\(sample.name)" : "\(currentPath)/\(sample.name)"
        downloader.start(remotePath: remotePath, transfer: transfer)
    }

    private func deletePath(for sample: SampleFile) -> String {
        currentPath == "/" ? "/\(sample.name)" : "\(currentPath)/\(sample.name)"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                // Back button when inside a subfolder
                if pathStack.count > 1 {
                    Button(action: navigateUp) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ConnektaktTheme.primary)
                    }
                    .buttonStyle(.plain)
                }

                Text(currentPath.uppercased())
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textSecondary)
                    .tracking(1)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if connection.isLoadingSamples {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(ConnektaktTheme.primary)
                } else {
                    Text("\(connection.samples.count) FILES")
                        .font(ConnektaktTheme.smallFont)
                        .foregroundStyle(ConnektaktTheme.textMuted)
                        .tracking(1)
                }

                Spacer()

                // Transfer backend badge (diagnostic)
                Text(connection.transferLabel)
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textMuted)
                    .tracking(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(ConnektaktTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(ConnektaktTheme.primary.opacity(0.3), lineWidth: 1)
                    )

                CKButton("UPLOAD", icon: "arrow.up", variant: .primary) {
                    importer.triggerFilePicker()
                }

                let canImport = selectedSample != nil && selectedSample?.isFolder == false
                CKButton("IMPORT", icon: "arrow.down", variant: .secondary) {
                    if let sample = selectedSample, !sample.isFolder {
                        startDownload(sample)
                    }
                }
                .disabled(!canImport)
                .opacity(canImport ? 1.0 : 0.35)
            }
            .padding(.horizontal, ConnektaktTheme.paddingMD)
            .padding(.vertical, ConnektaktTheme.paddingSM)
            .background(ConnektaktTheme.surface)

            // Selection status bar
            if let sel = selectedSample {
                HStack(spacing: 6) {
                    Image(systemName: sel.isFolder ? "folder" : "waveform")
                        .font(.system(size: 10))
                        .foregroundStyle(ConnektaktTheme.primary)
                    Text(sel.name)
                        .font(ConnektaktTheme.smallFont)
                        .foregroundStyle(ConnektaktTheme.primary)
                        .tracking(1)
                        .lineLimit(1)
                    Text("—")
                        .font(ConnektaktTheme.smallFont)
                        .foregroundStyle(ConnektaktTheme.textMuted)
                    Text(sel.sizeString)
                        .font(ConnektaktTheme.smallFont)
                        .foregroundStyle(ConnektaktTheme.textMuted)
                        .tracking(1)
                    Spacer()
                    Text("TAP IMPORT TO DOWNLOAD")
                        .font(ConnektaktTheme.smallFont)
                        .foregroundStyle(ConnektaktTheme.textMuted)
                        .tracking(1)
                        .opacity(sel.isFolder ? 0 : 1)
                }
                .padding(.horizontal, ConnektaktTheme.paddingMD)
                .padding(.vertical, 5)
                .background(ConnektaktTheme.primary.opacity(0.08))
            }

            Rectangle()
                .fill(ConnektaktTheme.primary.opacity(0.15))
                .frame(height: 1)

            // File list or error/empty state
            if let err = connection.sampleLoadError {
                SampleErrorView(message: err)
            } else if !connection.isLoadingSamples && connection.samples.isEmpty {
                SampleEmptyView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(connection.samples) { sample in
                            SampleRow(sample: sample, isSelected: selectedSample?.id == sample.id)
                                .onTapGesture(count: 2) {
                                    if sample.isFolder {
                                        navigate(into: sample)
                                    } else {
                                        selectedSample = sample
                                        startDownload(sample)
                                    }
                                }
                                .onTapGesture(count: 1) {
                                    selectedSample = sample
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if !sample.isFolder {
                                        Button(role: .destructive) {
                                            Task { await connection.deleteFile(at: deletePath(for: sample)) }
                                        } label: {
                                            Label("DELETE", systemImage: "trash")
                                        }
                                    }
                                }
                        }
                    }
                }
            }

            // Storage meter — only show when we have a known total
            if connection.totalStorageMB > 0 {
                CKStorageMeter(
                    usedMB: connection.usedStorageMB,
                    totalMB: connection.totalStorageMB
                )
            }
        }
        // Reset navigation on disconnect
        .onChange(of: connection.status) { _, newValue in
            if !newValue.isConnected { pathStack = ["/"] }
        }
        // File picker
        .fileImporter(
            isPresented: $importer.isShowingFilePicker,
            allowedContentTypes: [.audio, .wav, .aiff, .mp3, .mpeg4Audio],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { importer.handleFileSelected(url) }
            case .failure:
                break
            }
        }
        // Optimization sheet (analyze → optimize → ready to upload)
        .sheet(isPresented: Binding(
            get: { importer.showOptimizationSheet },
            set: { if !$0 { importer.dismiss() } }
        )) {
            OptimizationSheet(coordinator: importer, transfer: connection.transfer, destinationFolder: currentPath)
        }
        // Upload progress sheet
        .sheet(isPresented: Binding(
            get: { importer.showUploadSheet },
            set: { if !$0 { importer.dismiss() } }
        )) {
            UploadProgressSheet(coordinator: importer)
        }
        // Download progress sheet
        .sheet(isPresented: Binding(
            get: { downloader.isActive },
            set: { if !$0 { downloader.dismiss() } }
        )) {
            DownloadSheet(coordinator: downloader)
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

// MARK: - Error / Empty States

private struct SampleErrorView: View {
    @Environment(ConnectionManager.self) private var connection
    let message: String

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(ConnektaktTheme.accent)

            VStack(spacing: 6) {
                Text("SAMPLE LIST UNAVAILABLE")
                    .font(ConnektaktTheme.bodyFont)
                    .foregroundStyle(ConnektaktTheme.textPrimary)
                    .tracking(2)

                Text(message.uppercased())
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textSecondary)
                    .tracking(1)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, ConnektaktTheme.paddingLG)
            }

            CKButton("RETRY", icon: "arrow.clockwise", variant: .secondary) {
                Task { await connection.refreshSamples() }
            }
            Spacer()
        }
    }
}

private struct SampleEmptyView: View {
    @Environment(ConnectionManager.self) private var connection

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(ConnektaktTheme.textSecondary)

            Text("NO SAMPLES FOUND")
                .font(ConnektaktTheme.bodyFont)
                .foregroundStyle(ConnektaktTheme.textSecondary)
                .tracking(2)

            CKButton("REFRESH", icon: "arrow.clockwise", variant: .secondary) {
                Task { await connection.refreshSamples() }
            }
            Spacer()
        }
    }
}

// MARK: - Download Coordinator

@Observable
@MainActor
private final class DownloadCoordinator {
    enum Phase: Equatable {
        case idle
        case downloading(Double)
        case done(URL)
        case failed(String)

        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle): return true
            case (.downloading(let a), .downloading(let b)): return a == b
            case (.done(let a), .done(let b)): return a == b
            case (.failed(let a), .failed(let b)): return a == b
            default: return false
            }
        }
    }

    var phase: Phase = .idle

    var isActive: Bool {
        if case .idle = phase { return false }
        return true
    }

    func start(remotePath: String, transfer: any DigitaktTransferProtocol) {
        phase = .downloading(0)
        Task {
            do {
                let url = try await transfer.downloadSample(remotePath: remotePath) { [weak self] prog in
                    Task { @MainActor [weak self] in
                        if case .downloading = self?.phase {
                            self?.phase = .downloading(prog.fraction)
                        }
                    }
                }
                phase = .done(url)
            } catch {
                phase = .failed(error.localizedDescription.uppercased())
            }
        }
    }

    func dismiss() { phase = .idle }
}

// MARK: - Download Sheet

private struct DownloadSheet: View {
    var coordinator: DownloadCoordinator

    var body: some View {
        VStack(spacing: 0) {
            CKHeaderBar(title: headerTitle, status: .connected(deviceName: "DIGITAKT"))

            VStack(spacing: ConnektaktTheme.paddingXL) {
                Spacer(minLength: 20)

                switch coordinator.phase {
                case .downloading(let p):
                    downloadingContent(progress: p)
                case .done(let url):
                    doneContent(url: url)
                case .failed(let msg):
                    failedContent(message: msg)
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
        switch coordinator.phase {
        case .done:   return "DOWNLOAD COMPLETE"
        case .failed: return "DOWNLOAD FAILED"
        default:      return "DOWNLOADING..."
        }
    }

    @ViewBuilder
    private func downloadingContent(progress: Double) -> some View {
        VStack(spacing: ConnektaktTheme.paddingLG) {
            ProgressView()
                .scaleEffect(1.4)
                .tint(ConnektaktTheme.primary)

            Text("RECEIVING FROM DIGITAKT")
                .font(ConnektaktTheme.titleFont)
                .foregroundStyle(ConnektaktTheme.textPrimary)
                .tracking(2)

            CKProgressBar(progress: progress)

            Text(String(format: "%.0f%%", progress * 100))
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundStyle(ConnektaktTheme.primary)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func doneContent(url: URL) -> some View {
        VStack(spacing: ConnektaktTheme.paddingLG) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(ConnektaktTheme.waveformGreen)

            VStack(spacing: ConnektaktTheme.paddingXS) {
                Text("READY TO SAVE")
                    .font(ConnektaktTheme.largeFont)
                    .foregroundStyle(ConnektaktTheme.waveformGreen)
                    .tracking(2)

                Text(url.lastPathComponent)
                    .font(ConnektaktTheme.bodyFont)
                    .foregroundStyle(ConnektaktTheme.textSecondary)
                    .tracking(1)
            }

            ShareLink(item: url) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                    Text("SHARE / SAVE TO FILES")
                        .font(ConnektaktTheme.bodyFont)
                        .tracking(1)
                }
                .foregroundStyle(ConnektaktTheme.background)
                .padding(.horizontal, ConnektaktTheme.paddingMD)
                .padding(.vertical, ConnektaktTheme.paddingSM)
                .background(ConnektaktTheme.primary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            CKButton("DONE", icon: "checkmark", variant: .ghost) {
                coordinator.dismiss()
            }
        }
    }

    @ViewBuilder
    private func failedContent(message: String) -> some View {
        VStack(spacing: ConnektaktTheme.paddingLG) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(ConnektaktTheme.accent)

            Text("DOWNLOAD FAILED")
                .font(ConnektaktTheme.largeFont)
                .foregroundStyle(ConnektaktTheme.accent)
                .tracking(2)

            Text(message)
                .font(ConnektaktTheme.smallFont)
                .foregroundStyle(ConnektaktTheme.textSecondary)
                .tracking(1)
                .multilineTextAlignment(.center)

            CKButton("DISMISS", icon: "xmark", variant: .ghost) {
                coordinator.dismiss()
            }
        }
    }
}

#Preview {
    BrowserView()
        .environment(ConnectionManager())
}
