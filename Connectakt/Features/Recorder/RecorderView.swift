import SwiftUI

struct RecorderView: View {
    @Environment(ConnectionManager.self)       private var connection
    @Environment(AudioRecorder.self)           private var recorder
    @Environment(RecordingHistoryManager.self) private var history

    @State private var importer            = ImportCoordinator()
    @State private var pendingRecordURL:   URL? = nil
    @State private var lastRecordedSession: RecordingSession? = nil
    @State private var showTrimEditor      = false
    @State private var trimSession:        RecordingSession? = nil

    var body: some View {
        VStack(spacing: 0) {
            CKHeaderBar(title: "RECORD", status: connection.status)
            infoStrip
            Rectangle().fill(ConnektaktTheme.primary.opacity(0.15)).frame(height: 1)

            ScrollView {
                VStack(spacing: ConnektaktTheme.paddingMD) {
                    waveformSection
                    transportSection

                    RecordingHistoryView(onTrim: { session in
                        trimSession    = session
                        showTrimEditor = true
                    })
                    .ckPanel()
                    .padding(.horizontal, ConnektaktTheme.paddingMD)
                }
                .padding(.vertical, ConnektaktTheme.paddingMD)
            }
        }
        .ckScreen()
        // Finalize session once analysis completes
        .onChange(of: recorder.analysisState) { _, state in
            finalizeSessionIfReady(state)
        }
        // Trim editor sheet
        .sheet(isPresented: $showTrimEditor) {
            if let s = trimSession {
                RecordingTrimEditor(session: s) { _ in
                    showTrimEditor = false
                }
                .environment(connection)
            }
        }
        // Optimization sheet
        .sheet(isPresented: Binding(
            get: { importer.showOptimizationSheet },
            set: { if !$0 { importer.dismiss() } }
        )) {
            OptimizationSheet(coordinator: importer,
                              transfer: connection.transfer,
                              destinationFolder: "SAMPLES")
        }
        // Upload progress sheet
        .sheet(isPresented: Binding(
            get: { importer.showUploadSheet },
            set: { if !$0 { importer.dismiss() } }
        )) {
            UploadProgressSheet(coordinator: importer)
        }
    }

    // MARK: - Info Strip

    private var infoStrip: some View {
        HStack {
            infoCell(label: "INPUT",  value: connection.status.isConnected ? "DIGITAKT USB" : "NO DEVICE")
            Divider().background(ConnektaktTheme.textMuted).frame(height: 20)
            infoCell(label: "FORMAT", value: "PCM / 48KHZ")
            Divider().background(ConnektaktTheme.textMuted).frame(height: 20)
            infoCell(label: "STATUS", value: displayState.statusLabel, color: displayState.statusColor)
            if recorder.isMIDIClockActive {
                Divider().background(ConnektaktTheme.textMuted).frame(height: 20)
                HStack(spacing: 4) {
                    Circle()
                        .fill(ConnektaktTheme.waveformGreen)
                        .frame(width: 5, height: 5)
                    Text("CLK SYNC")
                        .font(ConnektaktTheme.smallFont)
                        .foregroundStyle(ConnektaktTheme.waveformGreen)
                        .tracking(1)
                }
            }
        }
        .padding(.horizontal, ConnektaktTheme.paddingMD)
        .padding(.vertical, ConnektaktTheme.paddingSM)
        .background(ConnektaktTheme.surface)
    }

    // MARK: - Waveform Section

    private var waveformSection: some View {
        VStack(spacing: ConnektaktTheme.paddingSM) {
            CKLiveWaveformView(
                levels: recorder.levels,
                color: recorder.isRecording ? ConnektaktTheme.danger : ConnektaktTheme.waveformGreen
            )
            .frame(height: 80)
            .padding(.horizontal, ConnektaktTheme.paddingLG)
            .ckPanel()
            .padding(.horizontal, ConnektaktTheme.paddingLG)

            HStack(alignment: .bottom, spacing: ConnektaktTheme.paddingLG) {
                // Primary position counter
                VStack(alignment: .leading, spacing: 1) {
                    if let pos = recorder.barBeatPos {
                        Text(pos.displayString)
                            .font(.system(size: 30, weight: .bold, design: .monospaced))
                            .foregroundStyle(recorder.isRecording
                                ? ConnektaktTheme.danger
                                : ConnektaktTheme.primary)
                            .monospacedDigit()
                        Text(formattedTime(recorder.elapsedSeconds))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(ConnektaktTheme.textMuted)
                            .monospacedDigit()
                    } else {
                        Text(formattedTime(recorder.elapsedSeconds))
                            .font(.system(size: 30, weight: .bold, design: .monospaced))
                            .foregroundStyle(recorder.isRecording
                                ? ConnektaktTheme.danger
                                : ConnektaktTheme.textPrimary)
                            .monospacedDigit()
                    }
                }

                Spacer()

                // BPM / analysis badge
                VStack(alignment: .trailing, spacing: 2) {
                    if let bpm = recorder.activeBPM {
                        Text(String(format: "%.1f", bpm))
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundStyle(recorder.isMIDIClockActive
                                ? ConnektaktTheme.waveformGreen
                                : ConnektaktTheme.primary)
                        Text(recorder.isMIDIClockActive ? "MIDI CLK" : "BPM")
                            .font(ConnektaktTheme.smallFont)
                            .foregroundStyle(ConnektaktTheme.textMuted)
                            .tracking(1)
                    }
                    if recorder.analysisState == .analyzing {
                        HStack(spacing: 4) {
                            ProgressView().scaleEffect(0.55).tint(ConnektaktTheme.primary)
                            Text("ANALYZING")
                                .font(ConnektaktTheme.smallFont)
                                .foregroundStyle(ConnektaktTheme.textMuted)
                                .tracking(1)
                        }
                    }
                }
            }
            .padding(.horizontal, ConnektaktTheme.paddingLG)
        }
    }

    // MARK: - Transport Section

    private var transportSection: some View {
        VStack(spacing: ConnektaktTheme.paddingMD) {
            // Big record button
            Button(action: toggleRecord) {
                ZStack {
                    Circle()
                        .strokeBorder(ConnektaktTheme.danger.opacity(0.5), lineWidth: 2)
                        .frame(width: 72, height: 72)
                    Circle()
                        .fill(ConnektaktTheme.danger)
                        .frame(width: recorder.isRecording ? 28 : 52)
                        .animation(.easeInOut(duration: 0.15), value: recorder.isRecording)
                }
            }
            .buttonStyle(.plain)
            .disabled(!connection.status.isConnected)
            .opacity(connection.status.isConnected ? 1.0 : 0.35)

            Text(recorder.isRecording ? "TAP TO STOP" : "TAP TO RECORD")
                .font(ConnektaktTheme.smallFont)
                .foregroundStyle(ConnektaktTheme.textSecondary)
                .tracking(2)

            // Secondary actions — shown after a recording is captured
            let sessionReady = lastRecordedSession != nil
            let analysing    = pendingRecordURL != nil && !sessionReady

            if pendingRecordURL != nil || sessionReady {
                HStack(spacing: ConnektaktTheme.paddingMD) {
                    CKButton("DISCARD", icon: "trash", variant: .ghost) {
                        pendingRecordURL    = nil
                        lastRecordedSession = nil
                    }
                    .opacity(analysing ? 0.4 : 1.0)
                    .disabled(analysing)

                    if sessionReady {
                        CKButton("TRIM", icon: "scissors", variant: .secondary) {
                            trimSession    = lastRecordedSession
                            showTrimEditor = true
                        }
                    }

                    CKButton("OPTIMIZE + UPLOAD", icon: "arrow.up.circle", variant: .primary) {
                        if let url = lastRecordedSession?.fileURL ?? pendingRecordURL {
                            importer.handleFileSelected(url)
                            pendingRecordURL    = nil
                            lastRecordedSession = nil
                        }
                    }
                    .disabled(!connection.status.isConnected || analysing)
                    .opacity(connection.status.isConnected && !analysing ? 1.0 : 0.35)
                }
            }

            if let error = recorder.lastError {
                Text(error)
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.danger)
                    .tracking(1)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }

    // MARK: - Session Finalization

    private func finalizeSessionIfReady(_ state: AnalysisState) {
        guard case .complete = state, let url = pendingRecordURL else { return }
        let attrs  = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size   = attrs?[.size] as? Int64 ?? 0
        let session = RecordingSession(
            fileURL:         url,
            durationSeconds: recorder.elapsedSeconds,
            bpm:             recorder.confirmedBPM.map { Int($0.rounded()) } ?? recorder.detectedBPM,
            beatPhase:       recorder.beatPhase,
            fileSizeBytes:   size
        )
        history.add(session)
        lastRecordedSession = session
        pendingRecordURL    = nil
    }

    // MARK: - Computed Display State

    private var displayState: RecorderDisplayState {
        if recorder.isRecording { return .recording }
        if lastRecordedSession != nil || pendingRecordURL != nil { return .stopped }
        return .idle
    }

    // MARK: - Actions

    private func toggleRecord() {
        if recorder.isRecording {
            if let url = recorder.stopRecording() {
                pendingRecordURL    = url
                lastRecordedSession = nil
            }
        } else {
            pendingRecordURL    = nil
            lastRecordedSession = nil
            do {
                try recorder.startRecording()
            } catch {
                recorder.lastError = error.localizedDescription
            }
        }
    }

    // MARK: - Helpers

    private func formattedTime(_ t: TimeInterval) -> String {
        let m  = Int(t) / 60
        let s  = Int(t) % 60
        let cs = Int((t.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", m, s, cs)
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

// MARK: - Display State

private enum RecorderDisplayState {
    case idle, recording, stopped

    var statusLabel: String {
        switch self {
        case .idle:      return "READY"
        case .recording: return "● REC"
        case .stopped:   return "STOPPED"
        }
    }

    var statusColor: Color {
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
        .environment(AudioRecorder())
        .environment(RecordingHistoryManager())
}
