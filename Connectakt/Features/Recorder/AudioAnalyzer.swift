import AVFoundation
import Accelerate
import Foundation

// MARK: - Result

struct AudioAnalysis {
    let bpm: Double           // detected tempo (BPM)
    let beatPhase: Double     // seconds from file start to first beat onset
    let confidence: Double    // 0.0 ... 1.0
    let durationSeconds: Double

    var intBPM: Int { Int(bpm.rounded()) }

    func makeGrid() -> MusicalGrid {
        MusicalGrid(bpm: bpm, beatPhase: beatPhase)
    }
}

// MARK: - Errors

enum AudioAnalysisError: LocalizedError {
    case fileNotReadable
    case tooShort
    case analysisFailed

    var errorDescription: String? {
        switch self {
        case .fileNotReadable: return "CANNOT READ AUDIO FILE"
        case .tooShort:        return "RECORDING TOO SHORT FOR TEMPO ANALYSIS"
        case .analysisFailed:  return "TEMPO ANALYSIS FAILED"
        }
    }
}

// MARK: - Analyzer

/// Post-recording tempo analysis using onset-function autocorrelation.
/// All work happens on a detached background task and is CPU-bound only.
final class AudioAnalyzer {

    static let minimumDurationSeconds: Double = 1.5

    /// Async entry point — safe to call from `@MainActor` contexts.
    static func analyze(url: URL) async -> AudioAnalysis? {
        await Task.detached(priority: .userInitiated) {
            try? analyzeSync(url: url)
        }.value
    }

    // MARK: - Synchronous core (runs on detached task)

    private static func analyzeSync(url: URL) throws -> AudioAnalysis {
        guard let file = try? AVAudioFile(forReading: url) else {
            throw AudioAnalysisError.fileNotReadable
        }

        let format      = file.processingFormat
        let sr          = format.sampleRate
        let totalFrames = Int(file.length)
        let duration    = Double(totalFrames) / sr

        guard duration >= minimumDurationSeconds else { throw AudioAnalysisError.tooShort }

        // Cap at 60 s to avoid huge allocations
        let readFrames = min(totalFrames, Int(60.0 * sr))
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(readFrames)) else {
            throw AudioAnalysisError.analysisFailed
        }
        try file.read(into: buf, frameCount: AVAudioFrameCount(readFrames))
        guard let ch = buf.floatChannelData else { throw AudioAnalysisError.analysisFailed }

        let N      = Int(buf.frameLength)
        let nCh    = Int(format.channelCount)

        // --- Mix to mono ---
        var mono = [Float](repeating: 0, count: N)
        if nCh >= 2 {
            var half: Float = 0.5
            vDSP_vadd(ch[0], 1, ch[1], 1, &mono, 1, vDSP_Length(N))
            vDSP_vsmul(mono, 1, &half, &mono, 1, vDSP_Length(N))
        } else {
            mono = Array(UnsafeBufferPointer(start: ch[0], count: N))
        }

        // --- Energy envelope: RMS per hop window (~11 ms) ---
        let hopSize = max(256, Int(sr * 0.011))
        let winSize = hopSize * 2
        var energy: [Float] = []
        energy.reserveCapacity(N / hopSize)
        var i = 0
        while i + winSize <= N {
            var rms: Float = 0
            mono.withUnsafeBufferPointer { ptr in
                vDSP_measqv(ptr.baseAddress! + i, 1, &rms, vDSP_Length(winSize))
            }
            energy.append(sqrt(rms))
            i += hopSize
        }
        let E = energy.count
        guard E > 8 else { throw AudioAnalysisError.tooShort }

        // --- Half-wave rectified first difference = onset strength function ---
        var onset = [Float](repeating: 0, count: E)
        for j in 1..<E { onset[j] = max(energy[j] - energy[j - 1], 0) }

        // Normalize
        var mx: Float = 0
        vDSP_maxv(onset, 1, &mx, vDSP_Length(E))
        if mx > 0 {
            var inv = 1.0 / mx
            vDSP_vsmul(onset, 1, &inv, &onset, 1, vDSP_Length(E))
        }

        // --- Autocorrelation over lag range covering 40–240 BPM ---
        let fps    = sr / Double(hopSize)            // onset frames per second
        let lagMin = max(1, Int(fps * 60.0 / 240.0)) // fastest: 240 BPM
        let lagMax = min(E - 1, Int(fps * 60.0 / 40.0)) // slowest: 40 BPM
        guard lagMin < lagMax else { throw AudioAnalysisError.tooShort }

        var bestLag = lagMin
        var bestAC:  Float = -1

        onset.withUnsafeBufferPointer { ptr in
            for lag in lagMin...lagMax {
                let len = vDSP_Length(E - lag)
                var ac: Float = 0
                vDSP_dotpr(ptr.baseAddress!, 1, ptr.baseAddress! + lag, 1, &ac, len)
                ac /= Float(E - lag)   // normalize by window size
                if ac > bestAC { bestAC = ac; bestLag = lag }
            }
        }

        // Convert lag → BPM and resolve octave ambiguity into 60–180 BPM range
        var rawBPM = fps * 60.0 / Double(bestLag)
        while rawBPM < 60  { rawBPM *= 2 }
        while rawBPM > 180 { rawBPM /= 2 }

        // --- Beat phase: first onset ≥ 30 % of max, within 2 beats of file start ---
        let searchLimit = min(Int(fps * 2.0 * 60.0 / rawBPM), E)
        var beatPhase   = 0.0
        if let idx = onset.prefix(searchLimit).firstIndex(where: { $0 >= 0.30 }) {
            beatPhase = Double(idx) * Double(hopSize) / sr
        }

        return AudioAnalysis(
            bpm:             rawBPM,
            beatPhase:       beatPhase,
            confidence:      Double(min(bestAC * 4, 1.0)),
            durationSeconds: duration
        )
    }
}

