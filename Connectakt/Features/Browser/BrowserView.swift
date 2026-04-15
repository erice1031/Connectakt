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
    @Environment(StoreManager.self)      private var store
    @State private var showPaywall = false
    @State private var selectedSample: SampleFile?
    @State private var importer        = ImportCoordinator()
    @State private var downloader      = DownloadCoordinator()
    @State private var batchDownloader = BatchDownloadCoordinator()
    @State private var batchImporter   = BatchImportCoordinator()
    @State private var pathStack: [String] = ["/"]
    @State private var isSelectMode        = false
    @State private var selectedFileIDs: Set<UUID> = []

    private var currentPath: String { pathStack.last ?? "/" }

    private func navigate(into folder: SampleFile) {
        guard folder.isFolder else { return }
        let next = currentPath == "/" ? "/\(folder.name)" : "\(currentPath)/\(folder.name)"
        pathStack.append(next)
        connection.lastBrowsedPath = next
        Task { await connection.refreshSamples(path: next) }
    }

    private func navigateUp() {
        guard pathStack.count > 1 else { return }
        pathStack.removeLast()
        connection.lastBrowsedPath = currentPath
        Task { await connection.refreshSamples(path: currentPath) }
    }

    private func startDownload(_ sample: SampleFile) {
        guard let transfer = connection.transfer else { return }
        let remotePath = currentPath == "/" ? "/\(sample.name)" : "\(currentPath)/\(sample.name)"
        downloader.start(remotePath: remotePath, transfer: transfer)
    }

    private func remotePathFor(_ sample: SampleFile) -> String {
        currentPath == "/" ? "/\(sample.name)" : "\(currentPath)/\(sample.name)"
    }

    private func enterSelectMode() {
        isSelectMode    = true
        selectedSample  = nil
        selectedFileIDs = []
    }

    private func exitSelectMode() {
        isSelectMode    = false
        selectedFileIDs = []
    }

    private func toggleSelection(_ sample: SampleFile) {
        guard !sample.isFolder else { return }
        if selectedFileIDs.contains(sample.id) {
            selectedFileIDs.remove(sample.id)
        } else {
            selectedFileIDs.insert(sample.id)
        }
    }

    private func startBatchDownload() {
        guard let transfer = connection.transfer else { return }
        let files = connection.samples
            .filter { !$0.isFolder && selectedFileIDs.contains($0.id) }
            .map { (remotePath: remotePathFor($0), name: $0.name) }
        guard !files.isEmpty else { return }
        batchDownloader.start(files: files, using: transfer)
        exitSelectMode()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            if isSelectMode {
                selectModeToolbar
            } else {
                normalToolbar
            }

            // Selection status bar (single-select mode only)
            if !isSelectMode, let sel = selectedSample {
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
                    Text("PRESS IMPORT TO DOWNLOAD")
                        .font(ConnektaktTheme.smallFont)
                        .foregroundStyle(ConnektaktTheme.textMuted)
                        .tracking(1)
                        .opacity(sel.isFolder ? 0 : 1)
                }
                .padding(.horizontal, ConnektaktTheme.paddingMD)
                .padding(.vertical, 5)
                .background(ConnektaktTheme.primary.opacity(0.08))
            }

            // Multi-select count bar
            if isSelectMode {
                HStack {
                    Text("\(selectedFileIDs.count) OF \(connection.samples.filter { !$0.isFolder }.count) FILES SELECTED")
                        .font(ConnektaktTheme.smallFont)
                        .foregroundStyle(selectedFileIDs.isEmpty ? ConnektaktTheme.textMuted : ConnektaktTheme.primary)
                        .tracking(1)
                    Spacer()
                    if !selectedFileIDs.isEmpty {
                        Button("SELECT ALL") {
                            selectedFileIDs = Set(connection.samples.filter { !$0.isFolder }.map { $0.id })
                        }
                        .font(ConnektaktTheme.smallFont)
                        .foregroundStyle(ConnektaktTheme.primary)
                    }
                }
                .padding(.horizontal, ConnektaktTheme.paddingMD)
                .padding(.vertical, 5)
                .background(ConnektaktTheme.primary.opacity(0.06))
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
                            SampleRow(
                                sample: sample,
                                isSelected: !isSelectMode && selectedSample?.id == sample.id,
                                isChecked: isSelectMode && selectedFileIDs.contains(sample.id),
                                isSelectMode: isSelectMode
                            )
                            .onTapGesture {
                                if isSelectMode {
                                    toggleSelection(sample)
                                } else if sample.isFolder {
                                    navigate(into: sample)
                                } else {
                                    selectedSample = sample
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if !isSelectMode && !sample.isFolder {
                                    Button(role: .destructive) {
                                        Task { await connection.deleteFile(at: remotePathFor(sample)) }
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
            if !newValue.isConnected {
                pathStack = ["/"]
                exitSelectMode()
            }
        }
        // File picker (multi for Pro, single for free)
        .fileImporter(
            isPresented: $importer.isShowingFilePicker,
            allowedContentTypes: [.audio, .wav, .aiff, .mp3, .mpeg4Audio],
            allowsMultipleSelection: store.isPro
        ) { result in
            switch result {
            case .success(let urls):
                if urls.count == 1 {
                    importer.handleFileSelected(urls[0])
                } else if urls.count > 1, let transfer = connection.transfer {
                    batchImporter.start(urls: urls, using: transfer, destination: currentPath)
                }
            case .failure:
                break
            }
        }
        // Single-file: optimization sheet
        .sheet(isPresented: Binding(
            get: { importer.showOptimizationSheet },
            set: { if !$0 { importer.dismiss() } }
        )) {
            OptimizationSheet(coordinator: importer, transfer: connection.transfer, destinationFolder: currentPath)
        }
        // Single-file: upload progress sheet
        .sheet(isPresented: Binding(
            get: { importer.showUploadSheet },
            set: { if !$0 { importer.dismiss() } }
        )) {
            UploadProgressSheet(coordinator: importer)
        }
        // Single-file: download sheet
        .sheet(isPresented: Binding(
            get: { downloader.isActive },
            set: { if !$0 { downloader.dismiss() } }
        )) {
            DownloadSheet(coordinator: downloader)
        }
        // Batch download sheet
        .sheet(isPresented: Binding(
            get: { batchDownloader.isActive },
            set: { if !$0 { batchDownloader.dismiss() } }
        )) {
            BatchDownloadSheet(coordinator: batchDownloader)
        }
        // Batch upload sheet
        .sheet(isPresented: Binding(
            get: { batchImporter.isActive },
            set: { if !$0 { batchImporter.dismiss() } }
        )) {
            BatchUploadSheet(coordinator: batchImporter, destination: currentPath)
        }
        // Paywall
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environment(store)
        }
    }

    // MARK: - Toolbars

    private var normalToolbar: some View {
        HStack {
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
                ProgressView().scaleEffect(0.6).tint(ConnektaktTheme.primary)
            } else {
                Text("\(connection.samples.count) FILES")
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textMuted)
                    .tracking(1)
            }

            Spacer()

            Text(connection.transferLabel)
                .font(ConnektaktTheme.smallFont)
                .foregroundStyle(ConnektaktTheme.textMuted)
                .tracking(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(ConnektaktTheme.surface)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(ConnektaktTheme.primary.opacity(0.3), lineWidth: 1))

            CKButton("UPLOAD", icon: "arrow.up", variant: .primary) {
                importer.triggerFilePicker()
            }

            let canDownload = selectedSample?.isFolder == false
            CKButton("DOWNLOAD", icon: "arrow.down", variant: .secondary) {
                if let sample = selectedSample, !sample.isFolder { startDownload(sample) }
            }
            .disabled(!canDownload)
            .opacity(canDownload ? 1.0 : 0.35)

            CKButton("SELECT", icon: "checkmark.circle", variant: .ghost) {
                if store.isPro { enterSelectMode() } else { showPaywall = true }
            }
        }
        .padding(.horizontal, ConnektaktTheme.paddingMD)
        .padding(.vertical, ConnektaktTheme.paddingSM)
        .background(ConnektaktTheme.surface)
    }

    private var selectModeToolbar: some View {
        HStack {
            CKButton("CANCEL", variant: .ghost) { exitSelectMode() }

            Spacer()

            let count = selectedFileIDs.count
            let canDownload = count > 0 && connection.transfer != nil
            CKButton(
                count > 0 ? "DOWNLOAD (\(count))" : "DOWNLOAD",
                icon: "arrow.down.circle",
                variant: count > 0 ? .primary : .secondary
            ) {
                startBatchDownload()
            }
            .disabled(!canDownload)
            .opacity(canDownload ? 1.0 : 0.35)
        }
        .padding(.horizontal, ConnektaktTheme.paddingMD)
        .padding(.vertical, ConnektaktTheme.paddingSM)
        .background(ConnektaktTheme.surface)
    }
}

// MARK: - Sample Row

private struct SampleRow: View {
    let sample: SampleFile
    let isSelected:   Bool
    var isChecked:    Bool = false
    var isSelectMode: Bool = false

    var body: some View {
        HStack(spacing: ConnektaktTheme.paddingSM) {
            // Checkbox (select mode) or type icon (normal mode)
            if isSelectMode && !sample.isFolder {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isChecked ? ConnektaktTheme.primary : ConnektaktTheme.textMuted)
                    .frame(width: 20)
                    .animation(.easeInOut(duration: 0.1), value: isChecked)
            } else {
                Image(systemName: sample.isFolder ? "folder" : "waveform")
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? ConnektaktTheme.background : ConnektaktTheme.textSecondary)
                    .frame(width: 20)
            }

            Text(sample.name)
                .font(ConnektaktTheme.bodyFont)
                .foregroundStyle(
                    isChecked   ? ConnektaktTheme.textPrimary :
                    isSelected  ? ConnektaktTheme.background  :
                                  ConnektaktTheme.textPrimary
                )
                .lineLimit(1)

            Spacer()

            if !sample.isFolder {
                Text(sample.sizeString)
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(isSelected ? ConnektaktTheme.background.opacity(0.7) : ConnektaktTheme.textSecondary)
                    .monospacedDigit()
            }

            if !isSelectMode {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(isSelected ? ConnektaktTheme.background.opacity(0.5) : ConnektaktTheme.textMuted)
            }
        }
        .padding(.horizontal, ConnektaktTheme.paddingMD)
        .padding(.vertical, 10)
        .background(
            isChecked  ? ConnektaktTheme.primary.opacity(0.12) :
            isSelected ? ConnektaktTheme.primary               :
                         Color.clear
        )
        .overlay(Rectangle().fill(ConnektaktTheme.primary.opacity(0.1)).frame(height: 1), alignment: .bottom)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.1), value: isSelected)
        .animation(.easeInOut(duration: 0.1), value: isChecked)
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
    @Environment(ConnectionManager.self) private var connection
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

            #if os(macOS)
            CKButton("SAVE TO DISK...", icon: "arrow.down.circle") {
                let panel = NSSavePanel()
                panel.nameFieldStringValue = url.lastPathComponent
                panel.allowedContentTypes = [UTType.audio]
                panel.canCreateDirectories = true
                if panel.runModal() == .OK, let dest = panel.url,
                   let data = try? Data(contentsOf: url) {
                    try? data.write(to: dest)
                }
            }
            #else
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
            #endif

            CKButton("OPEN IN EDITOR", icon: "slider.horizontal.3") {
                connection.pendingEditorURL = url
                coordinator.dismiss()
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

// MARK: - Batch Download Sheet

private struct BatchDownloadSheet: View {
    var coordinator: BatchDownloadCoordinator

    var body: some View {
        VStack(spacing: 0) {
            CKHeaderBar(title: headerTitle, status: .connected(deviceName: "DIGITAKT"))

            if coordinator.isComplete {
                completeSummary
            } else {
                progressList
            }
        }
        .background(ConnektaktTheme.background)
        .presentationDetents([.medium, .large])
        .presentationBackground(ConnektaktTheme.background)
    }

    private var headerTitle: String {
        coordinator.isComplete ? "DOWNLOAD COMPLETE" : "DOWNLOADING \(coordinator.items.count) FILES"
    }

    private var progressList: some View {
        VStack(spacing: 0) {
            // Overall progress
            VStack(spacing: 8) {
                CKProgressBar(progress: coordinator.overallProgress)
                Text(String(format: "%.0f%%  —  %d / %d FILES",
                            coordinator.overallProgress * 100,
                            coordinator.items.filter { $0.status.progressFraction == 1 }.count,
                            coordinator.items.count))
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textMuted)
                    .tracking(1)
            }
            .padding(ConnektaktTheme.paddingMD)

            Rectangle().fill(ConnektaktTheme.primary.opacity(0.15)).frame(height: 1)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(coordinator.items) { item in
                        BatchItemRow(name: item.name, status: item.status)
                    }
                }
            }
        }
    }

    private var completeSummary: some View {
        VStack(spacing: ConnektaktTheme.paddingLG) {
            Spacer(minLength: 20)

            Image(systemName: coordinator.failedCount == 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(coordinator.failedCount == 0 ? ConnektaktTheme.waveformGreen : ConnektaktTheme.accent)

            VStack(spacing: 4) {
                Text("\(coordinator.doneURLs.count) FILES DOWNLOADED")
                    .font(ConnektaktTheme.largeFont)
                    .foregroundStyle(ConnektaktTheme.textPrimary)
                    .tracking(2)
                if coordinator.failedCount > 0 {
                    Text("\(coordinator.failedCount) FAILED")
                        .font(ConnektaktTheme.smallFont)
                        .foregroundStyle(ConnektaktTheme.accent)
                        .tracking(1)
                }
            }

            if !coordinator.doneURLs.isEmpty {
                ShareLink(items: coordinator.doneURLs) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .semibold))
                        Text("SHARE ALL / SAVE TO FILES")
                            .font(ConnektaktTheme.bodyFont)
                            .tracking(1)
                    }
                    .foregroundStyle(ConnektaktTheme.background)
                    .padding(.horizontal, ConnektaktTheme.paddingMD)
                    .padding(.vertical, ConnektaktTheme.paddingSM)
                    .background(ConnektaktTheme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            CKButton("DONE", icon: "checkmark", variant: .ghost) {
                coordinator.dismiss()
            }

            Spacer(minLength: 20)
        }
        .padding(ConnektaktTheme.paddingLG)
    }
}

// MARK: - Batch Upload Sheet

private struct BatchUploadSheet: View {
    var coordinator: BatchImportCoordinator
    let destination: String

    var body: some View {
        VStack(spacing: 0) {
            CKHeaderBar(title: headerTitle, status: .connected(deviceName: "DIGITAKT"))

            if coordinator.isComplete {
                completeSummary
            } else {
                progressList
            }
        }
        .background(ConnektaktTheme.background)
        .presentationDetents([.medium, .large])
        .presentationBackground(ConnektaktTheme.background)
    }

    private var headerTitle: String {
        coordinator.isComplete ? "UPLOAD COMPLETE" : "UPLOADING \(coordinator.items.count) FILES"
    }

    private var progressList: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                CKProgressBar(progress: coordinator.overallProgress)
                Text(String(format: "%.0f%%  —  %d / %d FILES",
                            coordinator.overallProgress * 100,
                            coordinator.doneCount,
                            coordinator.items.count))
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textMuted)
                    .tracking(1)
            }
            .padding(ConnektaktTheme.paddingMD)

            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 10))
                    .foregroundStyle(ConnektaktTheme.textMuted)
                Text((destination == "/" ? "/ (ROOT)" : destination).uppercased())
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textMuted)
                    .tracking(1)
                Spacer()
            }
            .padding(.horizontal, ConnektaktTheme.paddingMD)
            .padding(.bottom, 8)

            Rectangle().fill(ConnektaktTheme.primary.opacity(0.15)).frame(height: 1)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(coordinator.items) { item in
                        BatchItemRow(name: item.name, status: item.status)
                    }
                }
            }
        }
    }

    private var completeSummary: some View {
        VStack(spacing: ConnektaktTheme.paddingLG) {
            Spacer(minLength: 20)

            Image(systemName: coordinator.failedCount == 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(coordinator.failedCount == 0 ? ConnektaktTheme.waveformGreen : ConnektaktTheme.accent)

            VStack(spacing: 4) {
                Text("\(coordinator.doneCount) FILES UPLOADED")
                    .font(ConnektaktTheme.largeFont)
                    .foregroundStyle(ConnektaktTheme.textPrimary)
                    .tracking(2)
                if coordinator.failedCount > 0 {
                    Text("\(coordinator.failedCount) FAILED")
                        .font(ConnektaktTheme.smallFont)
                        .foregroundStyle(ConnektaktTheme.accent)
                        .tracking(1)
                }
            }

            CKButton("DONE", icon: "checkmark", variant: .ghost) {
                coordinator.dismiss()
            }

            Spacer(minLength: 20)
        }
        .padding(ConnektaktTheme.paddingLG)
    }
}

// MARK: - Batch Item Row (shared)

private struct BatchItemRow<S: Equatable>: View {
    let name: String
    let status: S

    // We need concrete rendering — use two specializations via protocol trick.
    // Instead, accept the display strings directly.
    fileprivate init(name: String, status: BatchDownloadCoordinator.ItemStatus) where S == BatchDownloadCoordinator.ItemStatus {
        self.name   = name
        self.status = status
        self._label = Self.downloadLabel(status)
        self._progress = status.progressFraction
        self._isDone   = { if case .done   = status { return true }; return false }()
        self._isFailed = { if case .failed = status { return true }; return false }()
    }

    fileprivate init(name: String, status: BatchImportCoordinator.ItemStatus) where S == BatchImportCoordinator.ItemStatus {
        self.name   = name
        self.status = status
        self._label    = status.label
        self._progress = status.progressFraction
        self._isDone   = { if case .done   = status { return true }; return false }()
        self._isFailed = { if case .failed = status { return true }; return false }()
    }

    private let _label:    String
    private let _progress: Double
    private let _isDone:   Bool
    private let _isFailed: Bool

    private static func downloadLabel(_ s: BatchDownloadCoordinator.ItemStatus) -> String {
        switch s {
        case .pending:            return "WAITING"
        case .downloading(let p): return String(format: "DOWNLOADING %.0f%%", p * 100)
        case .done:               return "✓ DONE"
        case .failed(let msg):    return "✗ \(msg)"
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: _isDone ? "checkmark.circle.fill" : _isFailed ? "exclamationmark.circle" : "arrow.down.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(_isDone ? ConnektaktTheme.waveformGreen : _isFailed ? ConnektaktTheme.accent : ConnektaktTheme.primary)
                    .frame(width: 16)
                Text(name)
                    .font(ConnektaktTheme.bodyFont)
                    .foregroundStyle(ConnektaktTheme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text(_label)
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(_isDone ? ConnektaktTheme.waveformGreen : _isFailed ? ConnektaktTheme.accent : ConnektaktTheme.textMuted)
                    .tracking(1)
            }
            if !_isDone && !_isFailed && _progress > 0 {
                CKProgressBar(progress: _progress)
                    .padding(.leading, ConnektaktTheme.paddingLG)
            }
        }
        .padding(.horizontal, ConnektaktTheme.paddingMD)
        .padding(.vertical, 10)
        .overlay(Rectangle().fill(ConnektaktTheme.primary.opacity(0.1)).frame(height: 1), alignment: .bottom)
    }
}

#Preview {
    BrowserView()
        .environment(ConnectionManager())
}
