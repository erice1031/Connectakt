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
                CKButton("IMPORT", icon: "arrow.down", variant: .secondary) {}
            }
            .padding(.horizontal, ConnektaktTheme.paddingMD)
            .padding(.vertical, ConnektaktTheme.paddingSM)
            .background(ConnektaktTheme.surface)

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
                                    if sample.isFolder { navigate(into: sample) }
                                }
                                .onTapGesture(count: 1) {
                                    selectedSample = sample
                                }
                        }
                    }
                }
            }

            // Storage meter
            CKStorageMeter(
                usedMB: connection.usedStorageMB,
                totalMB: connection.totalStorageMB
            )
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
            OptimizationSheet(coordinator: importer, transfer: connection.transfer)
        }
        // Upload progress sheet
        .sheet(isPresented: Binding(
            get: { importer.showUploadSheet },
            set: { if !$0 { importer.dismiss() } }
        )) {
            UploadProgressSheet(coordinator: importer)
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

#Preview {
    BrowserView()
        .environment(ConnectionManager())
}
