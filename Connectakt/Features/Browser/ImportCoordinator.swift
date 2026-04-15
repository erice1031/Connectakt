import Observation
import SwiftUI

// MARK: - Import Phase

enum ImportPhase: Equatable {
    case idle
    case analyzing
    case readyToOptimize(AudioFormatInfo)
    case optimizing(Double)                 // 0.0 ... 1.0
    case readyToUpload(OptimizationResult)
    case uploading(Double)                  // 0.0 ... 1.0
    case done(String)                       // filename on device
    case failed(String)                     // error description
}

// MARK: - Import Coordinator

@Observable
@MainActor
final class ImportCoordinator {

    var phase: ImportPhase = .idle
    var isShowingFilePicker = false

    private let optimizer = AudioOptimizer()

    // MARK: Sheet Visibility

    var showOptimizationSheet: Bool {
        switch phase {
        case .readyToOptimize, .optimizing, .readyToUpload: return true
        default: return false
        }
    }

    var showUploadSheet: Bool {
        switch phase {
        case .uploading, .done: return true
        default: return false
        }
    }

    // MARK: Derived State

    var formatInfo: AudioFormatInfo? {
        switch phase {
        case .readyToOptimize(let info): return info
        default: return nil
        }
    }

    var optimizationResult: OptimizationResult? {
        switch phase {
        case .readyToUpload(let result): return result
        default: return nil
        }
    }

    var optimizationProgress: Double {
        if case .optimizing(let p) = phase { return p }
        return 0
    }

    var uploadProgress: Double {
        if case .uploading(let p) = phase { return p }
        return 0
    }

    // MARK: - Actions

    func triggerFilePicker() {
        isShowingFilePicker = true
    }

    func handleFileSelected(_ url: URL) {
        phase = .analyzing
        Task {
            // Security-scoped URLs come from the file picker (user-picked files).
            // Local URLs (e.g. recordings in temporaryDirectory) are not security-scoped;
            // startAccessingSecurityScopedResource returns false for them — that's fine.
            let hasScopeAccess = url.startAccessingSecurityScopedResource()
            defer { if hasScopeAccess { url.stopAccessingSecurityScopedResource() } }

            do {
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(url.lastPathComponent)

                // Skip the copy if the file is already at the target temp path
                // (e.g. a recording from AudioRecorder that lives in temporaryDirectory).
                let sameFile = url.standardizedFileURL.path == tempURL.standardizedFileURL.path
                if !sameFile {
                    if FileManager.default.fileExists(atPath: tempURL.path) {
                        try FileManager.default.removeItem(at: tempURL)
                    }
                    try FileManager.default.copyItem(at: url, to: tempURL)
                }

                let info = try await AudioOptimizer.analyzeFormat(at: sameFile ? url : tempURL)
                phase = .readyToOptimize(info)

            } catch {
                phase = .failed(error.localizedDescription.uppercased())
            }
        }
    }

    func beginOptimization() {
        guard case .readyToOptimize(let info) = phase else { return }
        phase = .optimizing(0)

        Task {
            do {
                let result = try await optimizer.optimize(url: info.url) { [weak self] p in
                    Task { @MainActor [weak self] in
                        if case .optimizing = self?.phase {
                            self?.phase = .optimizing(p)
                        }
                    }
                }
                phase = .readyToUpload(result)
            } catch {
                phase = .failed(error.localizedDescription.uppercased())
            }
        }
    }

    func beginUpload(using transfer: (any DigitaktTransferProtocol)?, destinationFolder: String = "SAMPLES") {
        guard case .readyToUpload(let result) = phase, let transfer else { return }
        phase = .uploading(0)

        Task {
            do {
                // Normalize to a full path with leading slash.
                // "/samples" → "/samples/file.wav", "/" or "" → "/file.wav"
                let folder: String
                if destinationFolder == "/" || destinationFolder.isEmpty {
                    folder = ""
                } else if destinationFolder.hasPrefix("/") {
                    folder = destinationFolder
                } else {
                    folder = "/\(destinationFolder)"
                }
                let remotePath = "\(folder)/\(result.outputURL.lastPathComponent)"
                try await transfer.uploadSample(
                    localURL: result.outputURL,
                    remotePath: remotePath
                ) { [weak self] transferProgress in
                    Task { @MainActor [weak self] in
                        if case .uploading = self?.phase {
                            self?.phase = .uploading(transferProgress.fraction)
                        }
                    }
                }
                // Cleanup temp file
                try? FileManager.default.removeItem(at: result.outputURL)
                phase = .done(result.outputURL.lastPathComponent)
            } catch {
                phase = .failed(error.localizedDescription.uppercased())
            }
        }
    }

    func dismiss() {
        // Clean up any temp files if we were mid-optimization
        if case .readyToUpload(let result) = phase {
            try? FileManager.default.removeItem(at: result.outputURL)
        }
        phase = .idle
    }
}
