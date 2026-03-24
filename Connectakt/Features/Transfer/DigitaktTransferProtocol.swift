import Foundation

// MARK: - Transfer Types

struct TransferProgress: Equatable {
    let bytesTransferred: Int64
    let totalBytes: Int64
    var fraction: Double { Double(bytesTransferred) / Double(max(totalBytes, 1)) }
    var percentString: String { String(format: "%d%%", Int(fraction * 100)) }
}

struct StorageInfo {
    let usedBytes: Int64
    let totalBytes: Int64
    var usedMB: Int    { Int(usedBytes  / 1_048_576) }
    var totalMB: Int   { Int(totalBytes / 1_048_576) }
    var fraction: Double { Double(usedBytes) / Double(max(totalBytes, 1)) }
}

// MARK: - Protocol

protocol DigitaktTransferProtocol: AnyObject {
    func uploadSample(
        localURL: URL,
        remotePath: String,
        progress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws

    func downloadSample(
        remotePath: String,
        progress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws -> URL

    func listFiles(remotePath: String) async throws -> [SampleFile]
    func deleteFile(remotePath: String) async throws
    func getStorageInfo() async throws -> StorageInfo
}

// MARK: - Mock Implementation

final class MockDigitaktTransfer: DigitaktTransferProtocol {

    func uploadSample(
        localURL: URL,
        remotePath: String,
        progress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws {
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64) ?? 500_000
        let steps = 20
        for i in 1...steps {
            try await Task.sleep(nanoseconds: 80_000_000)  // 80ms per step = ~1.6s total
            let transferred = Int64(i) * (fileSize / Int64(steps))
            await MainActor.run {
                progress(TransferProgress(bytesTransferred: transferred, totalBytes: fileSize))
            }
        }
    }

    func downloadSample(
        remotePath: String,
        progress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws -> URL {
        let fakeSize: Int64 = 1_048_576
        let steps = 10
        for i in 1...steps {
            try await Task.sleep(nanoseconds: 80_000_000)
            let transferred = Int64(i) * (fakeSize / Int64(steps))
            await MainActor.run {
                progress(TransferProgress(bytesTransferred: transferred, totalBytes: fakeSize))
            }
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(URL(fileURLWithPath: remotePath).lastPathComponent)
    }

    func listFiles(remotePath: String) async throws -> [SampleFile] {
        try await Task.sleep(nanoseconds: 300_000_000)
        return [
            SampleFile(name: "KICK_01.WAV",       size: 2_412_544, isFolder: false),
            SampleFile(name: "SNARE_DRY.WAV",     size: 1_153_433, isFolder: false),
            SampleFile(name: "HH_CLOSED.WAV",     size: 838_860,   isFolder: false),
            SampleFile(name: "BASS_LOOP_120.WAV", size: 3_354_394, isFolder: false),
            SampleFile(name: "VOCAL_CHOP_01.WAV", size: 1_572_864, isFolder: false),
        ]
    }

    func deleteFile(remotePath: String) async throws {
        try await Task.sleep(nanoseconds: 200_000_000)
    }

    func getStorageInfo() async throws -> StorageInfo {
        try await Task.sleep(nanoseconds: 100_000_000)
        return StorageInfo(usedBytes: 510_656_512, totalBytes: 734_003_200)
    }
}

// ElektronTransfer stub removed — replaced by ElektronMIDITransfer (Phase 3).
