import AVFoundation
import Observation

// MARK: - Errors

enum RecordingError: LocalizedError {
    case noInputAvailable
    case engineStartFailed(Error)
    case fileCreationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .noInputAvailable:         return "NO AUDIO INPUT DEVICE FOUND"
        case .engineStartFailed(let e): return "ENGINE FAILED: \(e.localizedDescription.uppercased())"
        case .fileCreationFailed(let e): return "FILE ERROR: \(e.localizedDescription.uppercased())"
        }
    }
}

// MARK: - AudioRecorder

/// Records audio from the default input (USB audio when Digitakt is connected).
/// All @Observable property mutations happen on MainActor.
@Observable
final class AudioRecorder {

    // MARK: Published State

    private(set) var isRecording = false
    private(set) var elapsedSeconds: Double = 0
    private(set) var levels: [Float] = Array(repeating: 0, count: 60)
    private(set) var detectedBPM: Int? = nil
    var lastError: String? = nil

    // MARK: Private

    private let engine = AVAudioEngine()
    private let bpmDetector = BPMDetector()
    private var outputFile: AVAudioFile?
    private var startDate: Date?
    private var clockTask: Task<Void, Never>?

    // MARK: - Start Recording

    func startRecording() throws {
        guard !isRecording else { return }

        lastError = nil
        detectedBPM = nil
        elapsedSeconds = 0

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true)
        #endif

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0 else {
            throw RecordingError.noInputAvailable
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CK_REC_\(Int(Date().timeIntervalSince1970)).caf")

        do {
            outputFile = try AVAudioFile(forWriting: url, settings: format.settings)
        } catch {
            throw RecordingError.fileCreationFailed(error)
        }

        bpmDetector.reset()

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.handleBuffer(buffer)
        }

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            outputFile = nil
            throw RecordingError.engineStartFailed(error)
        }

        isRecording = true
        startDate = Date()

        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard let self, let start = self.startDate else { continue }
                let elapsed = Date().timeIntervalSince(start)
                await MainActor.run { self.elapsedSeconds = elapsed }
            }
        }
    }

    // MARK: - Stop Recording

    /// Stops the engine and returns the URL of the recorded file, or `nil` if not recording.
    @discardableResult
    func stopRecording() -> URL? {
        guard isRecording else { return nil }

        engine.stop()
        engine.inputNode.removeTap(onBus: 0)

        let savedURL = outputFile?.url
        outputFile = nil

        clockTask?.cancel()
        clockTask = nil
        isRecording = false
        startDate = nil

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif

        return savedURL
    }

    // MARK: - Buffer Processing  (audio thread → MainActor for UI updates)

    private func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        // Write raw captured audio
        try? outputFile?.write(from: buffer)

        // Compute RMS for waveform + BPM detection
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0, let channelData = buffer.floatChannelData else { return }

        var sum: Float = 0
        let ch = channelData[0]
        for i in 0..<frameLength { sum += ch[i] * ch[i] }
        let rms = (sum / Float(frameLength)).squareRoot()
        let ts = Date().timeIntervalSinceReferenceDate

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
