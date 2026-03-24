import Foundation
import AVFoundation

// MARK: - Audio Format Info

struct AudioFormatInfo: Equatable {
    let url: URL
    let fileName: String
    let fileExtension: String        // "WAV", "MP3", etc.
    let durationSeconds: Double
    let sampleRate: Double           // e.g. 48000.0
    let channelCount: Int            // 1 = mono, 2 = stereo
    let bitDepth: Int?               // nil for lossy formats
    let isLossy: Bool
    let fileSizeBytes: Int64
    let formatDisplayName: String    // e.g. "PCM FLOAT 32-BIT", "MP3"

    // MARK: Derived

    var needsResample: Bool     { sampleRate != 44100.0 && sampleRate != 48000.0 || sampleRate == 48000.0 }
    var needsDownmix: Bool      { channelCount > 1 }
    var needsBitConvert: Bool   { bitDepth != 16 || isLossy }
    var isAlreadyDigitaktSpec: Bool { !needsResample && !needsDownmix && !needsBitConvert }

    var durationString: String {
        let m = Int(durationSeconds) / 60
        let s = Int(durationSeconds) % 60
        let ms = Int((durationSeconds.truncatingRemainder(dividingBy: 1)) * 10)
        return m > 0 ? String(format: "%d:%02d.%d SEC", m, s, ms) : String(format: "%d.%d SEC", s, ms)
    }

    var sampleRateString: String { String(format: "%.1f KHZ", sampleRate / 1000) }
    var channelString: String   { channelCount == 1 ? "MONO" : channelCount == 2 ? "STEREO" : "\(channelCount) CHAN" }
    var bitDepthString: String  { bitDepth.map { "\($0)-BIT" } ?? "LOSSY" }

    var conversionSteps: [ConversionStep] {
        var steps: [ConversionStep] = []
        if needsResample   { steps.append(.init(label: "SAMPLE RATE", from: sampleRateString, to: "44.1 KHZ")) }
        if needsDownmix    { steps.append(.init(label: "CHANNELS",    from: channelString,    to: "MONO")) }
        if needsBitConvert { steps.append(.init(label: "BIT DEPTH",   from: bitDepthString,   to: "16-BIT")) }
        return steps
    }

    /// Estimated output size in bytes: 44100 Hz × 2 bytes × 1 channel × duration
    var estimatedOutputSizeBytes: Int64 { Int64(44100 * 2 * max(1, Int(ceil(durationSeconds)))) }
}

struct ConversionStep {
    let label: String
    let from: String
    let to: String
}

// MARK: - Optimization Options

struct OptimizationOptions: Equatable {
    var sampleRate: Double = 44100.0
    var channelCount: UInt32 = 1
    var bitDepth: Int = 16
    var outputDirectory: URL = .temporaryDirectory

    static let digitaktSpec = OptimizationOptions()
}

// MARK: - Optimization Result

struct OptimizationResult: Equatable {
    let sourceInfo: AudioFormatInfo
    let outputURL: URL
    let outputFileSizeBytes: Int64
    let durationSeconds: Double
    let conversionDurationSeconds: Double
    let stepsApplied: [String]      // human-readable description of what changed

    var outputSizeString: String {
        let mb = Double(outputFileSizeBytes) / 1_048_576
        return mb < 1 ? String(format: "%.0f KB", mb * 1024) : String(format: "%.1f MB", mb)
    }
}

// MARK: - Errors

enum OptimizationError: LocalizedError {
    case noAudioTrack
    case readerStartFailed(String)
    case writerStartFailed(String)
    case readFailed(String)
    case writeFailed(String)
    case unsupportedFormat(String)
    case outputExists

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:              return "No audio track found in file."
        case .readerStartFailed(let e): return "Could not read audio: \(e)"
        case .writerStartFailed(let e): return "Could not write output: \(e)"
        case .readFailed(let e):        return "Read error: \(e)"
        case .writeFailed(let e):       return "Write error: \(e)"
        case .unsupportedFormat(let f): return "Unsupported format: \(f)"
        case .outputExists:             return "Output file already exists."
        }
    }
}
