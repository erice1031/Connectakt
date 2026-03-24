import AVFoundation
import AudioToolbox

// MARK: - AudioOptimizer

actor AudioOptimizer {

    // MARK: - Format Analysis

    /// Inspect an audio file and return format metadata.
    /// Must be called after .startAccessingSecurityScopedResource() at the call site.
    static func analyzeFormat(at url: URL) async throws -> AudioFormatInfo {
        // AVAudioFile handles WAV, AIFF, ALAC natively.
        // On iOS it also reads MP3 and AAC via ExtendedAudioFileServices.
        guard let audioFile = try? AVAudioFile(forReading: url) else {
            throw OptimizationError.unsupportedFormat(url.pathExtension)
        }

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let tracks  = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw OptimizationError.noAudioTrack }

        let processingFormat = audioFile.processingFormat
        let sampleRate   = processingFormat.sampleRate
        let channelCount = Int(processingFormat.channelCount)

        // Determine original format from the file format settings
        let fileSettings = audioFile.fileFormat.settings
        let formatID = fileSettings[AVFormatIDKey] as? UInt32 ?? kAudioFormatLinearPCM

        var bitDepth: Int?
        var isLossy = false
        var formatDisplayName: String

        switch formatID {
        case kAudioFormatLinearPCM:
            let bd      = fileSettings[AVLinearPCMBitDepthKey] as? Int ?? 16
            let isFloat = fileSettings[AVLinearPCMIsFloatKey]  as? Bool ?? false
            bitDepth    = bd
            formatDisplayName = isFloat ? "PCM FLOAT \(bd)-BIT" : "PCM INT \(bd)-BIT"

        case kAudioFormatMPEGLayer3:
            formatDisplayName = "MP3"
            isLossy = true

        case kAudioFormatMPEG4AAC:
            formatDisplayName = "AAC"
            isLossy = true

        case kAudioFormatAppleLossless:
            formatDisplayName = "ALAC"

        default:
            formatDisplayName = url.pathExtension.uppercased()
        }

        let fileAttr = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = fileAttr?[.size] as? Int64 ?? 0

        return AudioFormatInfo(
            url: url,
            fileName: url.deletingPathExtension().lastPathComponent.uppercased(),
            fileExtension: url.pathExtension.uppercased(),
            durationSeconds: CMTimeGetSeconds(duration),
            sampleRate: sampleRate,
            channelCount: channelCount,
            bitDepth: bitDepth,
            isLossy: isLossy,
            fileSizeBytes: fileSize,
            formatDisplayName: formatDisplayName
        )
    }

    // MARK: - Conversion Pipeline

    /// Convert any audio file to Digitakt-spec WAV.
    /// `progress` is called on a background thread; dispatch to MainActor in the callback.
    func optimize(
        url: URL,
        options: OptimizationOptions = .digitaktSpec,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> OptimizationResult {

        let wallStart = Date()
        let sourceInfo = try await AudioOptimizer.analyzeFormat(at: url)

        // Output URL in temp dir
        let outputName = sourceInfo.fileName + "_DT.wav"
        let outputURL  = options.outputDirectory.appendingPathComponent(outputName)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        // Target PCM: 16-bit, 44.1kHz, mono, interleaved
        let pcmSettings: [String: Any] = [
            AVFormatIDKey:               kAudioFormatLinearPCM,
            AVSampleRateKey:             options.sampleRate,
            AVNumberOfChannelsKey:       options.channelCount,
            AVLinearPCMBitDepthKey:      options.bitDepth,
            AVLinearPCMIsFloatKey:       false,
            AVLinearPCMIsBigEndianKey:   false,
            AVLinearPCMIsNonInterleaved: false
        ]

        // Reader: AVAssetReaderTrackOutput applies decode + resample + downmix in one pass
        let asset  = AVURLAsset(url: url)
        let dur    = try await asset.load(.duration)
        let durSec = CMTimeGetSeconds(dur)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = tracks.first else { throw OptimizationError.noAudioTrack }

        let reader       = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: pcmSettings)
        readerOutput.alwaysCopiesSampleData = false
        reader.add(readerOutput)

        // Writer: WAV file
        let writer      = try AVAssetWriter(outputURL: outputURL, fileType: .wav)
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: pcmSettings)
        writerInput.expectsMediaDataInRealTime = false
        writer.add(writerInput)

        // Start — writer first, then reader
        guard writer.startWriting() else {
            throw OptimizationError.writerStartFailed(writer.error?.localizedDescription ?? "unknown")
        }
        guard reader.startReading() else {
            throw OptimizationError.readerStartFailed(reader.error?.localizedDescription ?? "unknown")
        }
        writer.startSession(atSourceTime: .zero)

        // Sample-buffer loop
        var lastReported = 0.0
        while reader.status == .reading {
            guard writerInput.isReadyForMoreMediaData else {
                await Task.yield(); continue
            }
            guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else { break }

            writerInput.append(sampleBuffer)

            // Monotonic progress estimate via presentation timestamp
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if durSec > 0 {
                let p = min(CMTimeGetSeconds(pts) / durSec, 0.99)
                if p > lastReported {
                    lastReported = p
                    progress(p)
                }
            }
        }

        if reader.status == .failed {
            throw OptimizationError.readFailed(reader.error?.localizedDescription ?? "read failed")
        }

        writerInput.markAsFinished()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            writer.finishWriting { c.resume() }
        }

        if writer.status == .failed {
            throw OptimizationError.writeFailed(writer.error?.localizedDescription ?? "write failed")
        }

        progress(1.0)

        let outputSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64) ?? 0
        let elapsed    = Date().timeIntervalSince(wallStart)
        let steps      = sourceInfo.conversionSteps.map { "\($0.label): \($0.from) → \($0.to)" }

        return OptimizationResult(
            sourceInfo: sourceInfo,
            outputURL: outputURL,
            outputFileSizeBytes: outputSize,
            durationSeconds: durSec,
            conversionDurationSeconds: elapsed,
            stepsApplied: steps.isEmpty ? ["PASSTHROUGH (ALREADY OPTIMAL)"] : steps
        )
    }
}
