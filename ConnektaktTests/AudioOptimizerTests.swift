import Testing
import AVFoundation
import Foundation
@testable import Connectakt

// MARK: - AudioOptimizer Tests

@Suite("AudioOptimizer")
struct AudioOptimizerTests {

    // MARK: - WAV Synthesis Helper (interleaved Int16 — widest compatibility)

    /// Write a minimal valid WAV (PCM Int16, interleaved) to a temp file.
    static func makeWAV(
        sampleRate: Int,
        channels: Int,
        bitDepth: Int = 16,
        duration: Double = 0.5
    ) throws -> URL {
        let frameCount = Int(Double(sampleRate) * duration)
        let bytesPerSample = bitDepth / 8
        let dataSize = frameCount * channels * bytesPerSample

        var wav = Data()

        // RIFF header
        wav.append(contentsOf: Array("RIFF".utf8))
        wav.append(littleEndian32: UInt32(36 + dataSize))
        wav.append(contentsOf: Array("WAVE".utf8))

        // fmt chunk
        wav.append(contentsOf: Array("fmt ".utf8))
        wav.append(littleEndian32: 16)                          // chunk size
        wav.append(littleEndian16: 1)                           // PCM
        wav.append(littleEndian16: UInt16(channels))
        wav.append(littleEndian32: UInt32(sampleRate))
        wav.append(littleEndian32: UInt32(sampleRate * channels * bytesPerSample))  // byte rate
        wav.append(littleEndian16: UInt16(channels * bytesPerSample))               // block align
        wav.append(littleEndian16: UInt16(bitDepth))

        // data chunk
        wav.append(contentsOf: Array("data".utf8))
        wav.append(littleEndian32: UInt32(dataSize))

        // PCM data: 440 Hz sine wave
        for i in 0..<frameCount {
            let t = Double(i) / Double(sampleRate)
            let sample = Int16(sin(2 * Double.pi * 440 * t) * 16000)
            for _ in 0..<channels {
                wav.append(littleEndian16: UInt16(bitPattern: sample))
            }
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ck_test_\(sampleRate)hz_\(channels)ch_\(bitDepth)b_\(UUID().uuidString).wav")
        try wav.write(to: url)
        return url
    }

    /// Parse the fmt chunk of a WAV file by scanning RIFF chunks — works regardless of chunk order.
    static func parseWAV(url: URL) throws -> (channels: Int, sampleRate: Int, bitsPerSample: Int) {
        let data = try Data(contentsOf: url)
        guard data.count >= 12 else { throw ParseError.tooShort }

        // Scan RIFF chunks starting after "RIFF????WAVE" (first 12 bytes)
        var pos = 12
        while pos + 8 <= data.count {
            let id = String(bytes: data[pos..<pos+4], encoding: .ascii) ?? ""
            let chunkSize = Int(data.u32(at: pos + 4))

            if id == "fmt ", chunkSize >= 16 {
                // fmt chunk layout (relative to start of chunk data = pos+8):
                // +0 wFormatTag, +2 nChannels, +4 nSamplesPerSec, +12 wBitsPerSample
                return (
                    channels:      Int(data.u16(at: pos + 10)),
                    sampleRate:    Int(data.u32(at: pos + 12)),
                    bitsPerSample: Int(data.u16(at: pos + 22))
                )
            }
            // Advance to next chunk (size + possible pad byte for odd-length chunks)
            pos += 8 + chunkSize + (chunkSize & 1)
        }
        throw ParseError.noFmtChunk
    }

    enum ParseError: Error { case tooShort, noFmtChunk }

    // MARK: - Model Tests (synchronous)

    @Test("AudioFormatInfo: stereo 48kHz identifies all needed conversions")
    func audioFormatInfoConversionSteps() {
        let info = AudioFormatInfo(
            url: URL(fileURLWithPath: "/tmp/test.wav"),
            fileName: "TEST", fileExtension: "WAV",
            durationSeconds: 2.0,
            sampleRate: 48000, channelCount: 2,
            bitDepth: 24, isLossy: false,
            fileSizeBytes: 200_000,
            formatDisplayName: "PCM INT 24-BIT"
        )
        #expect(info.needsResample   == true)
        #expect(info.needsDownmix    == true)
        #expect(info.needsBitConvert == true)
        #expect(info.isAlreadyDigitaktSpec == false)
        #expect(info.conversionSteps.count == 3)
    }

    @Test("AudioFormatInfo: mono 44.1kHz 16-bit is already optimal")
    func audioFormatInfoAlreadyOptimal() {
        let info = AudioFormatInfo(
            url: URL(fileURLWithPath: "/tmp/test.wav"),
            fileName: "KICK", fileExtension: "WAV",
            durationSeconds: 1.0,
            sampleRate: 44100, channelCount: 1,
            bitDepth: 16, isLossy: false,
            fileSizeBytes: 88_200,
            formatDisplayName: "PCM INT 16-BIT"
        )
        #expect(info.needsResample   == false)
        #expect(info.needsDownmix    == false)
        #expect(info.isAlreadyDigitaktSpec == true)
        #expect(info.conversionSteps.isEmpty)
    }

    @Test("AudioFormatInfo: lossy MP3 requires conversion")
    func audioFormatInfoLossy() {
        let info = AudioFormatInfo(
            url: URL(fileURLWithPath: "/tmp/test.mp3"),
            fileName: "SAMPLE", fileExtension: "MP3",
            durationSeconds: 3.0,
            sampleRate: 44100, channelCount: 2,
            bitDepth: nil, isLossy: true,
            fileSizeBytes: 300_000,
            formatDisplayName: "MP3"
        )
        #expect(info.isLossy         == true)
        #expect(info.needsBitConvert == true)   // lossy → requires lossless re-encode
        #expect(info.isAlreadyDigitaktSpec == false)
    }

    @Test("OptimizationOptions: digitaktSpec has correct defaults")
    func optimizationOptionsDefaults() {
        let opts = OptimizationOptions.digitaktSpec
        #expect(opts.sampleRate   == 44100.0)
        #expect(opts.channelCount == 1)
        #expect(opts.bitDepth     == 16)
    }

    // MARK: - AudioOptimizer Integration Tests (async)

    @Test("Optimizer converts stereo 48kHz 16-bit WAV to mono 44.1kHz 16-bit")
    func optimizerConvertsStereoToMono() async throws {
        let inputURL = try Self.makeWAV(sampleRate: 48000, channels: 2, duration: 0.3)
        defer { try? FileManager.default.removeItem(at: inputURL) }

        let optimizer = AudioOptimizer()
        let result = try await optimizer.optimize(url: inputURL) { _ in }
        defer { try? FileManager.default.removeItem(at: result.outputURL) }

        let header = try Self.parseWAV(url: result.outputURL)
        #expect(header.channels == 1)
        #expect(header.sampleRate == 44100)
        #expect(header.bitsPerSample == 16)
        #expect(result.outputFileSizeBytes > 0)
    }

    @Test("Optimizer output filename has _DT.wav suffix")
    func optimizerOutputSuffix() async throws {
        let inputURL = try Self.makeWAV(sampleRate: 48000, channels: 2, duration: 0.2)
        defer { try? FileManager.default.removeItem(at: inputURL) }

        let optimizer = AudioOptimizer()
        let result = try await optimizer.optimize(url: inputURL) { _ in }
        defer { try? FileManager.default.removeItem(at: result.outputURL) }

        #expect(result.outputURL.lastPathComponent.hasSuffix("_DT.wav"))
    }

    @Test("Optimizer progress callback reaches 1.0")
    func optimizerProgressCallback() async throws {
        let inputURL = try Self.makeWAV(sampleRate: 48000, channels: 2, duration: 0.3)
        defer { try? FileManager.default.removeItem(at: inputURL) }

        let progressBox = ProgressBox()
        let optimizer = AudioOptimizer()
        let result = try await optimizer.optimize(url: inputURL) { p in
            progressBox.set(p)
        }
        defer { try? FileManager.default.removeItem(at: result.outputURL) }

        #expect(progressBox.value == 1.0)
    }

    @Test("analyzeFormat returns correct metadata for stereo 48kHz")
    func analyzeFormatStereo48k() async throws {
        let inputURL = try Self.makeWAV(sampleRate: 48000, channels: 2, duration: 0.2)
        defer { try? FileManager.default.removeItem(at: inputURL) }

        let info = try await AudioOptimizer.analyzeFormat(at: inputURL)
        #expect(info.sampleRate   == 48000)
        #expect(info.channelCount == 2)
        #expect(info.needsResample == true)
        #expect(info.needsDownmix  == true)
    }
}

// MARK: - Data Helpers

private extension Data {
    mutating func append(littleEndian16 value: UInt16) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 2))
    }
    mutating func append(littleEndian32 value: UInt32) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 4))
    }
    func u16(at offset: Int) -> UInt16 {
        withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt16.self) }
    }
    func u32(at offset: Int) -> UInt32 {
        withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self) }
    }
}

private final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0.0

    var value: Double {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func set(_ newValue: Double) {
        lock.lock()
        storage = newValue
        lock.unlock()
    }
}
