import AVFoundation
import Observation

// MARK: - Errors

enum RecordingError: LocalizedError {
    case noInputAvailable
    case engineStartFailed(Error)
    case fileCreationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .noInputAvailable:           return "NO AUDIO INPUT DEVICE FOUND"
        case .engineStartFailed(let e):   return "ENGINE FAILED: \(e.localizedDescription.uppercased())"
        case .fileCreationFailed(let e):  return "FILE ERROR: \(e.localizedDescription.uppercased())"
        }
    }
}

// MARK: - Analysis State

enum AnalysisState: Equatable {
    case idle
    case analyzing
    case complete
    case failed(String)
}

// MARK: - AudioRecorder

/// Records audio from the default input (USB audio when Digitakt is connected).
/// Integrates MIDI clock (0xF8) for live tempo sync and runs post-recording
/// autocorrelation analysis to build an accurate MusicalGrid.
@Observable
final class AudioRecorder {

    // MARK: - Published recording state

    private(set) var isRecording    = false
    private(set) var elapsedSeconds: Double = 0
    private(set) var levels:         [Float] = Array(repeating: 0, count: 60)
    private(set) var detectedBPM:    Int? = nil   // live onset-based estimate
    var lastError: String? = nil

    // MARK: - Published tempo / grid state

    private(set) var analysisState: AnalysisState = .idle
    private(set) var confirmedBPM:  Double? = nil  // from post-recording analysis
    private(set) var beatPhase:     Double  = 0    // seconds-to-beat-1 from analysis
    private(set) var musicalGrid:   MusicalGrid? = nil

    /// Bar:beat position computed from elapsedSeconds + musicalGrid (live counter).
    var barBeatPos: BarBeatPos? {
        musicalGrid?.barBeat(at: elapsedSeconds)
    }

    // MARK: - MIDI clock

    private let midiClock = MIDIClockReceiver()

    var isMIDIClockActive: Bool { midiClock.isActive }

    /// Best available BPM: MIDI clock > confirmed analysis > live detected.
    var activeBPM: Double? {
        if let midi = midiClock.bpm { return midi }
        if let conf = confirmedBPM  { return conf }
        return detectedBPM.map(Double.init)
    }

    // MARK: - Private

    private let engine       = AVAudioEngine()
    private let bpmDetector  = BPMDetector()
    private var outputFile:  AVAudioFile?
    private var startDate:   Date?
    private var clockTask:   Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?

    // MARK: - Start Recording

    func startRecording() throws {
        guard !isRecording else { return }

        lastError     = nil
        detectedBPM   = nil
        confirmedBPM  = nil
        beatPhase     = 0
        musicalGrid   = nil
        elapsedSeconds = 0
        analysisState  = .idle

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true)
        #endif

        let inputNode = engine.inputNode
        let format    = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw RecordingError.noInputAvailable }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CK_REC_\(Int(Date().timeIntervalSince1970)).caf")

        do {
            outputFile = try AVAudioFile(forWriting: url, settings: format.settings)
        } catch {
            throw RecordingError.fileCreationFailed(error)
        }

        bpmDetector.reset()
        midiClock.start()

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.handleBuffer(buffer)
        }

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            outputFile = nil
            midiClock.stop()
            throw RecordingError.engineStartFailed(error)
        }

        isRecording = true
        startDate   = Date()

        // Clock loop: update elapsed time + sync musicalGrid from MIDI clock
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000) // 50 ms
                guard let self, let start = self.startDate else { continue }
                let elapsed     = Date().timeIntervalSince(start)
                let midiClockBPM = self.midiClock.bpm

                await MainActor.run {
                    self.elapsedSeconds = elapsed

                    // Keep musicalGrid updated from MIDI clock in real-time
                    if let midi = midiClockBPM {
                        if self.musicalGrid?.bpm != midi {
                            self.musicalGrid = MusicalGrid(bpm: midi, beatPhase: 0)
                        }
                    } else if self.musicalGrid == nil, let live = self.detectedBPM {
                        self.musicalGrid = MusicalGrid(bpm: Double(live), beatPhase: 0)
                    }
                }
            }
        }
    }

    // MARK: - Stop Recording

    /// Stops the engine and returns the recorded file URL.
    /// Analysis begins automatically in the background; observe `analysisState`
    /// for completion.
    @discardableResult
    func stopRecording() -> URL? {
        guard isRecording else { return nil }

        engine.stop()
        engine.inputNode.removeTap(onBus: 0)

        let savedURL = outputFile?.url
        outputFile   = nil

        clockTask?.cancel()
        clockTask    = nil
        isRecording  = false
        startDate    = nil

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif

        // Keep MIDI clock running for a moment — it may still be active on hardware
        // and its BPM is used as the grid source after recording.

        // Run post-recording tempo analysis in background
        if let url = savedURL {
            let midiClockSnapshot = midiClock.bpm
            runAnalysis(url: url, midiClockBPM: midiClockSnapshot)
        }

        return savedURL
    }

    // MARK: - Post-recording Analysis

    private func runAnalysis(url: URL, midiClockBPM: Double?) {
        analysisState = .analyzing
        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            guard let self else { return }

            let result = await AudioAnalyzer.analyze(url: url)

            await MainActor.run {
                if let r = result {
                    // Prefer MIDI clock BPM (most accurate) but use analysis for beat phase
                    let finalBPM: Double
                    if let midi = midiClockBPM {
                        finalBPM = midi
                    } else {
                        finalBPM = r.bpm
                    }
                    self.confirmedBPM = finalBPM
                    self.beatPhase    = r.beatPhase
                    self.musicalGrid  = MusicalGrid(bpm: finalBPM, beatPhase: r.beatPhase)
                    self.analysisState = .complete
                } else if let midi = midiClockBPM {
                    // Analysis failed but we have a MIDI clock reference
                    self.confirmedBPM  = midi
                    self.beatPhase     = 0
                    self.musicalGrid   = MusicalGrid(bpm: midi, beatPhase: 0)
                    self.analysisState = .complete
                } else {
                    self.analysisState = .failed("TEMPO ANALYSIS FAILED")
                }
            }
        }
    }

    // MARK: - Buffer Processing (audio thread → MainActor for UI)

    private func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        try? outputFile?.write(from: buffer)

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0, let channelData = buffer.floatChannelData else { return }

        var sum: Float = 0
        let ch = channelData[0]
        for i in 0..<frameLength { sum += ch[i] * ch[i] }
        let rms = (sum / Float(frameLength)).squareRoot()
        let ts  = Date().timeIntervalSinceReferenceDate

        let bpmResult = bpmDetector.feed(rms: rms, timestamp: ts)

        Task { @MainActor [weak self] in
            guard let self else { return }
            var updated = self.levels
            updated.removeFirst()
            updated.append(min(rms * 5, 1.0))
            self.levels = updated
            if let b = bpmResult { self.detectedBPM = b }
        }
    }
}
