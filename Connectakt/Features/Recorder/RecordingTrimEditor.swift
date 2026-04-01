import AVFoundation
import Accelerate
import SwiftUI

// MARK: - Trim Editor

/// Full-screen trim editor for a recorded session.
/// Draws the waveform, beat grid, and draggable snap-aware trim handles.
/// Self-contained: owns its own ImportCoordinator for the optimize → upload flow.
struct RecordingTrimEditor: View {

    let session: RecordingSession
    /// Called with the trimmed audio URL when the user confirms.
    /// The sheet is NOT automatically dismissed — the caller or onSend handler should do that.
    let onSend: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionManager.self) private var connection

    // MARK: Waveform state

    @State private var waveformPeaks: [Float] = []
    @State private var isLoadingWaveform = true

    // MARK: Trim state

    @State private var trimStart: Double = 0
    @State private var trimEnd:   Double = 0   // initialized in .task

    private enum TrimHandle { case start, end }
    @State private var activeHandle: TrimHandle? = nil

    // MARK: Snap state

    @State private var snapEnabled      = true
    @State private var snapQuantization = SnapQuantization.beat

    // MARK: Export state

    @State private var isTrimming = false
    @State private var importer   = ImportCoordinator()

    // MARK: - Derived

    private var duration: Double { session.durationSeconds }

    private var musicalGrid: MusicalGrid? {
        guard let bpm = session.bpm else { return nil }
        return MusicalGrid(bpm: Double(bpm), beatPhase: session.beatPhase ?? 0)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            CKHeaderBar(title: "TRIM EDITOR", status: .connected(deviceName: session.displayName))

            Rectangle().fill(ConnektaktTheme.primary.opacity(0.15)).frame(height: 1)

            ScrollView {
                VStack(spacing: 0) {
                    waveformSection
                    positionStrip
                    snapControls
                    Spacer(minLength: ConnektaktTheme.paddingLG)
                    actionButtons
                    Spacer(minLength: ConnektaktTheme.paddingLG)
                }
            }
        }
        .ckScreen()
        .task { await setupView() }
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

    // MARK: - Waveform Section

    private var waveformSection: some View {
        GeometryReader { geo in
            ZStack {
                if isLoadingWaveform {
                    ProgressView()
                        .tint(ConnektaktTheme.primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    waveformCanvas(geo: geo)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { drag in handleDrag(drag.location, width: geo.size.width) }
                                .onEnded   { _    in activeHandle = nil }
                        )
                }
            }
            .background(ConnektaktTheme.surface)
        }
        .frame(height: 130)
        .padding(.horizontal, ConnektaktTheme.paddingMD)
        .padding(.top, ConnektaktTheme.paddingMD)
    }

    private func waveformCanvas(geo: GeometryProxy) -> some View {
        Canvas { context, size in
            drawWaveform(context: &context, size: size, geo: geo)
        }
    }

    private func drawWaveform(context: inout GraphicsContext, size: CGSize, geo: GeometryProxy) {
        let w = size.width, h = size.height

        // 1. Waveform bars — green inside trim region, dimmed outside
        if !waveformPeaks.isEmpty {
            let barW = w / CGFloat(waveformPeaks.count)
            let midY = h / 2
            for (i, peak) in waveformPeaks.enumerated() {
                let x    = CGFloat(i) * barW
                let t    = Double(x / w) * duration
                let half = CGFloat(peak) * midY * 0.88
                let inTrim = t >= trimStart && t <= trimEnd
                let col  = inTrim
                    ? ConnektaktTheme.waveformGreen
                    : ConnektaktTheme.waveformGreen.opacity(0.18)
                let rect = CGRect(x: x, y: midY - half, width: max(barW - 0.5, 0.5), height: half * 2)
                context.fill(Path(rect), with: .color(col))
            }
        }

        // 2. Beat grid lines
        if let grid = musicalGrid {
            let range = 0.0...duration
            // Bar lines — brighter
            for t in grid.barTimes(in: range) {
                let x = CGFloat(t / duration) * w
                var path = Path(); path.move(to: .init(x: x, y: 0)); path.addLine(to: .init(x: x, y: h))
                context.stroke(path, with: .color(ConnektaktTheme.primary.opacity(0.55)), lineWidth: 1)
            }
            // Beat lines — dimmer
            for t in grid.beatTimes(in: range) {
                let x = CGFloat(t / duration) * w
                // Skip if coincides with a bar line
                if grid.barTimes(in: range).contains(where: { abs($0 - t) < 0.001 }) { continue }
                var path = Path(); path.move(to: .init(x: x, y: 0)); path.addLine(to: .init(x: x, y: h))
                context.stroke(path, with: .color(ConnektaktTheme.primary.opacity(0.2)), lineWidth: 0.5)
            }
        }

        // 3. Trim shading — darken outside the trim region
        let sx = CGFloat(trimStart / max(duration, 0.001)) * w
        let ex = CGFloat(trimEnd   / max(duration, 0.001)) * w
        let shade = ConnektaktTheme.background.opacity(0.62)
        context.fill(Path(CGRect(x: 0,  y: 0, width: sx,     height: h)), with: .color(shade))
        context.fill(Path(CGRect(x: ex, y: 0, width: w - ex, height: h)), with: .color(shade))

        // 4. Start handle — green vertical line + top knob
        let kh: CGFloat = 16
        context.stroke(Path { p in p.move(to: .init(x: sx, y: 0)); p.addLine(to: .init(x: sx, y: h)) },
                       with: .color(ConnektaktTheme.waveformGreen), lineWidth: 2)
        context.fill(Path(roundedRect: CGRect(x: sx - 7, y: 0, width: 14, height: kh), cornerRadius: 3),
                     with: .color(ConnektaktTheme.waveformGreen))

        // 5. End handle — accent vertical line + bottom knob
        context.stroke(Path { p in p.move(to: .init(x: ex, y: 0)); p.addLine(to: .init(x: ex, y: h)) },
                       with: .color(ConnektaktTheme.accent), lineWidth: 2)
        context.fill(Path(roundedRect: CGRect(x: ex - 7, y: h - kh, width: 14, height: kh), cornerRadius: 3),
                     with: .color(ConnektaktTheme.accent))
    }

    // MARK: - Position Strip

    private var positionStrip: some View {
        HStack(spacing: 0) {
            positionCell(label: "IN",  seconds: trimStart, color: ConnektaktTheme.waveformGreen)
            Divider().frame(height: 44).background(ConnektaktTheme.textMuted)
            lengthCell
            Divider().frame(height: 44).background(ConnektaktTheme.textMuted)
            positionCell(label: "OUT", seconds: trimEnd,   color: ConnektaktTheme.accent)
        }
        .padding(.horizontal, ConnektaktTheme.paddingMD)
        .padding(.vertical, ConnektaktTheme.paddingSM)
        .background(ConnektaktTheme.surface)
    }

    @ViewBuilder
    private func positionCell(label: String, seconds: Double, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(ConnektaktTheme.smallFont)
                .foregroundStyle(ConnektaktTheme.textMuted)
                .tracking(1)
            if let grid = musicalGrid {
                Text(grid.barBeat(at: seconds).displayString)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                    .monospacedDigit()
            }
            Text(formatSeconds(seconds))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(ConnektaktTheme.textSecondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var lengthCell: some View {
        VStack(spacing: 2) {
            Text("LEN")
                .font(ConnektaktTheme.smallFont)
                .foregroundStyle(ConnektaktTheme.textMuted)
                .tracking(1)
            if let grid = musicalGrid {
                let bars = (trimEnd - trimStart) / grid.secondsPerBar
                Text(String(format: "%.2f BAR", bars))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(ConnektaktTheme.textPrimary)
                    .monospacedDigit()
            }
            Text(formatSeconds(trimEnd - trimStart))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(ConnektaktTheme.textSecondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Snap Controls

    private var snapControls: some View {
        HStack(spacing: ConnektaktTheme.paddingSM) {
            // Snap toggle
            Button {
                withAnimation(.easeInOut(duration: 0.1)) { snapEnabled.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: snapEnabled ? "magnet.fill" : "magnet")
                        .font(.system(size: 11))
                    Text("SNAP")
                        .font(ConnektaktTheme.smallFont)
                        .tracking(1)
                }
                .foregroundStyle(snapEnabled ? ConnektaktTheme.primary : ConnektaktTheme.textMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(snapEnabled
                    ? ConnektaktTheme.primary.opacity(0.15)
                    : ConnektaktTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)

            Rectangle().fill(ConnektaktTheme.primary.opacity(0.2)).frame(width: 1, height: 20)

            // Quantization selector
            ForEach(SnapQuantization.allCases) { q in
                Button(q.rawValue) { snapQuantization = q }
                    .font(ConnektaktTheme.smallFont)
                    .tracking(1)
                    .foregroundStyle(snapQuantization == q && snapEnabled
                        ? ConnektaktTheme.background
                        : ConnektaktTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(snapQuantization == q && snapEnabled
                        ? ConnektaktTheme.primary
                        : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .buttonStyle(.plain)
                    .disabled(!snapEnabled || musicalGrid == nil)
                    .opacity(!snapEnabled || musicalGrid == nil ? 0.35 : 1.0)
            }

            Spacer()

            // BPM badge
            if let bpm = session.bpm {
                Text("\(bpm) BPM")
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textMuted)
                    .tracking(1)
            } else {
                Text("NO TEMPO")
                    .font(ConnektaktTheme.smallFont)
                    .foregroundStyle(ConnektaktTheme.textMuted)
                    .tracking(1)
            }
        }
        .padding(.horizontal, ConnektaktTheme.paddingMD)
        .padding(.vertical, ConnektaktTheme.paddingSM)
        .background(ConnektaktTheme.surface)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: ConnektaktTheme.paddingMD) {
            CKButton("CANCEL", icon: "xmark", variant: .ghost) {
                dismiss()
            }

            Spacer()

            if isTrimming {
                ProgressView().tint(ConnektaktTheme.primary)
            } else {
                CKButton("TRIM + UPLOAD", icon: "arrow.up.circle.fill", variant: .primary) {
                    executeTrim()
                }
                .disabled(!connection.status.isConnected)
                .opacity(connection.status.isConnected ? 1 : 0.4)
            }
        }
        .padding(.horizontal, ConnektaktTheme.paddingMD)
        .padding(.top, ConnektaktTheme.paddingMD)
    }

    // MARK: - Drag Handling

    private func handleDrag(_ location: CGPoint, width: CGFloat) {
        guard width > 0, duration > 0 else { return }
        let rawTime = Double(location.x / width) * duration

        // Determine which handle on first touch
        if activeHandle == nil {
            let startX = CGFloat(trimStart / duration) * width
            let endX   = CGFloat(trimEnd   / duration) * width
            activeHandle = abs(location.x - startX) <= abs(location.x - endX) ? .start : .end
        }

        let target: Double
        if snapEnabled, let grid = musicalGrid {
            target = grid.snapped(rawTime.clamped(to: 0...duration), to: snapQuantization)
        } else {
            target = rawTime.clamped(to: 0...duration)
        }

        switch activeHandle! {
        case .start: trimStart = min(target, trimEnd   - 0.05)
        case .end:   trimEnd   = max(target, trimStart + 0.05)
        }
    }

    // MARK: - Setup

    private func setupView() async {
        trimEnd      = session.durationSeconds
        waveformPeaks = await loadWaveformPeaks(url: session.fileURL)
        isLoadingWaveform = false
    }

    // MARK: - Waveform Loading

    private func loadWaveformPeaks(url: URL, resolution: Int = 512) async -> [Float] {
        await Task.detached(priority: .userInitiated) {
            guard let file = try? AVAudioFile(forReading: url) else { return [] }
            let format      = file.processingFormat
            let totalFrames = Int(file.length)
            guard totalFrames > 0 else { return [] }

            let framesPerBucket = max(1, totalFrames / resolution)
            var peaks = [Float](repeating: 0, count: resolution)
            var bucketIdx   = 0
            var bucketPeak: Float = 0
            var bucketCount = 0

            let chunkSize: AVAudioFrameCount = 8192
            guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else { return [] }

            while bucketIdx < resolution {
                buf.frameLength = 0
                do { try file.read(into: buf, frameCount: chunkSize) } catch { break }
                let nRead = Int(buf.frameLength)
                if nRead == 0 { break }
                guard let ch = buf.floatChannelData else { break }

                for f in 0..<nRead {
                    let val = abs(ch[0][f])
                    if val > bucketPeak { bucketPeak = val }
                    bucketCount += 1
                    if bucketCount >= framesPerBucket {
                        if bucketIdx < resolution { peaks[bucketIdx] = bucketPeak }
                        bucketIdx  += 1
                        bucketPeak  = 0
                        bucketCount = 0
                    }
                }
            }

            // Normalize to 0...1
            if let mx = peaks.max(), mx > 0 {
                let inv = 1.0 / mx
                return peaks.map { $0 * inv }
            }
            return peaks
        }.value
    }

    // MARK: - Trim + Export

    private func executeTrim() {
        isTrimming = true
        Task {
            if let outURL = await trimAudio(from: session.fileURL, start: trimStart, end: trimEnd) {
                await MainActor.run {
                    isTrimming = false
                    importer.handleFileSelected(outURL)
                    onSend(outURL)
                }
            } else {
                await MainActor.run { isTrimming = false }
            }
        }
    }

    private func trimAudio(from url: URL, start: Double, end: Double) async -> URL? {
        await Task.detached(priority: .userInitiated) {
            guard let file = try? AVAudioFile(forReading: url) else { return nil }
            let sr       = file.processingFormat.sampleRate
            let startFr  = AVAudioFramePosition(start * sr)
            let count    = AVAudioFrameCount(max(0, (end - start) * sr))
            guard count > 0 else { return nil }

            file.framePosition = startFr
            guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                             frameCapacity: count) else { return nil }
            guard (try? file.read(into: buf, frameCount: count)) != nil else { return nil }

            let outURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("CK_TRIM_\(Int(Date().timeIntervalSince1970)).caf")
            guard let outFile = try? AVAudioFile(forWriting: outURL,
                                                 settings: file.processingFormat.settings) else { return nil }
            guard (try? outFile.write(from: buf)) != nil else { return nil }
            return outURL
        }.value
    }

    // MARK: - Formatting

    private func formatSeconds(_ t: Double) -> String {
        let t   = max(t, 0)
        let m   = Int(t) / 60
        let s   = t - Double(m * 60)
        return String(format: "%02d:%05.2f", m, s)
    }
}

// MARK: - Clamp helper

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
