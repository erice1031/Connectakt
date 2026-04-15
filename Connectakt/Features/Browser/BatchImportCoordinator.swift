import Foundation

// MARK: - BatchImportCoordinator
//
// Drives a sequential queue of local file → optimize → Digitakt uploads.
// Each item goes through: pending → optimizing → uploading → done/failed.

@Observable
@MainActor
final class BatchImportCoordinator {

    // MARK: - Item

    enum ItemStatus: Equatable {
        case pending
        case optimizing(Double)
        case uploading(Double)
        case done(String)   // remote filename
        case failed(String)

        static func == (lhs: ItemStatus, rhs: ItemStatus) -> Bool {
            switch (lhs, rhs) {
            case (.pending, .pending):                        return true
            case (.optimizing(let a), .optimizing(let b)):   return a == b
            case (.uploading(let a), .uploading(let b)):     return a == b
            case (.done(let a), .done(let b)):               return a == b
            case (.failed(let a), .failed(let b)):           return a == b
            default:                                          return false
            }
        }

        var progressFraction: Double {
            switch self {
            case .pending:            return 0
            case .optimizing(let p):  return p * 0.5          // optimize = first 50%
            case .uploading(let p):   return 0.5 + p * 0.5   // upload   = second 50%
            case .done, .failed:      return 1
            }
        }

        var label: String {
            switch self {
            case .pending:            return "WAITING"
            case .optimizing(let p):  return String(format: "CONVERTING %.0f%%", p * 100)
            case .uploading(let p):   return String(format: "UPLOADING %.0f%%", p * 100)
            case .done(let name):     return "✓ \(name)"
            case .failed(let msg):    return "✗ \(msg)"
            }
        }
    }

    struct Item: Identifiable {
        let id         = UUID()
        let sourceURL:  URL
        let name:       String
        var status:     ItemStatus = .pending

        init(url: URL) {
            self.sourceURL = url
            self.name      = url.lastPathComponent
        }
    }

    // MARK: - State

    var items: [Item] = []
    var isActive: Bool { !items.isEmpty }

    var overallProgress: Double {
        guard !items.isEmpty else { return 0 }
        return items.reduce(0.0) { $0 + $1.status.progressFraction } / Double(items.count)
    }

    var isComplete: Bool {
        !items.isEmpty && items.allSatisfy {
            if case .done   = $0.status { return true }
            if case .failed = $0.status { return true }
            return false
        }
    }

    var doneCount:   Int { items.filter { if case .done   = $0.status { return true }; return false }.count }
    var failedCount: Int { items.filter { if case .failed = $0.status { return true }; return false }.count }

    private let optimizer = AudioOptimizer()

    // MARK: - Actions

    func start(urls: [URL],
               using transfer: any DigitaktTransferProtocol,
               destination: String) {
        items = urls.map { Item(url: $0) }
        Task {
            for i in items.indices {
                await processItem(at: i, transfer: transfer, destination: destination)
            }
        }
    }

    func dismiss() { items = [] }

    // MARK: - Private

    private func processItem(at index: Int,
                              transfer: any DigitaktTransferProtocol,
                              destination: String) async {
        let url = items[index].sourceURL
        let hasScopeAccess = url.startAccessingSecurityScopedResource()
        defer { if hasScopeAccess { url.stopAccessingSecurityScopedResource() } }

        do {
            // Copy to temp (skip if already there)
            let tempURL  = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
            let sameFile = url.standardizedFileURL.path == tempURL.standardizedFileURL.path
            if !sameFile {
                if FileManager.default.fileExists(atPath: tempURL.path) {
                    try FileManager.default.removeItem(at: tempURL)
                }
                try FileManager.default.copyItem(at: url, to: tempURL)
            }
            let workURL = sameFile ? url : tempURL

            // Optimize
            items[index].status = .optimizing(0)
            let result = try await optimizer.optimize(url: workURL) { [weak self] p in
                Task { @MainActor [weak self] in
                    guard let self, index < self.items.count,
                          case .optimizing = self.items[index].status else { return }
                    self.items[index].status = .optimizing(p)
                }
            }

            // Build remote path (always leading slash)
            items[index].status = .uploading(0)
            let folder: String
            if destination == "/" || destination.isEmpty {
                folder = ""
            } else {
                folder = destination.hasPrefix("/") ? destination : "/\(destination)"
            }
            let remotePath = "\(folder)/\(result.outputURL.lastPathComponent)"

            try await transfer.uploadSample(localURL: result.outputURL, remotePath: remotePath) { [weak self] prog in
                Task { @MainActor [weak self] in
                    guard let self, index < self.items.count,
                          case .uploading = self.items[index].status else { return }
                    self.items[index].status = .uploading(prog.fraction)
                }
            }
            try? FileManager.default.removeItem(at: result.outputURL)
            items[index].status = .done(result.outputURL.lastPathComponent)

        } catch {
            items[index].status = .failed(error.localizedDescription.uppercased())
        }
    }
}
