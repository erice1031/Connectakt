import Foundation

// MARK: - BatchDownloadCoordinator
//
// Drives a sequential queue of Digitakt → iPhone downloads.
// Each item tracks its own progress; overall progress is derived.

@Observable
@MainActor
final class BatchDownloadCoordinator {

    // MARK: - Item

    enum ItemStatus: Equatable {
        case pending
        case downloading(Double)
        case done(URL)
        case failed(String)

        static func == (lhs: ItemStatus, rhs: ItemStatus) -> Bool {
            switch (lhs, rhs) {
            case (.pending, .pending):                      return true
            case (.downloading(let a), .downloading(let b)): return a == b
            case (.done(let a), .done(let b)):              return a == b
            case (.failed(let a), .failed(let b)):          return a == b
            default:                                        return false
            }
        }

        var progressFraction: Double {
            switch self {
            case .pending:            return 0
            case .downloading(let p): return p
            case .done, .failed:      return 1
            }
        }

        var doneURL: URL? {
            if case .done(let u) = self { return u }
            return nil
        }
    }

    struct Item: Identifiable {
        let id         = UUID()
        let remotePath: String
        let name:       String
        var status:     ItemStatus = .pending
    }

    // MARK: - State

    var items:    [Item] = []
    var isActive: Bool   = false

    var overallProgress: Double {
        guard !items.isEmpty else { return 0 }
        return items.reduce(0.0) { $0 + $1.status.progressFraction } / Double(items.count)
    }

    var isComplete: Bool {
        !items.isEmpty && items.allSatisfy {
            if case .done    = $0.status { return true }
            if case .failed  = $0.status { return true }
            return false
        }
    }

    var doneURLs: [URL] { items.compactMap { $0.status.doneURL } }

    var failedCount: Int { items.filter { if case .failed = $0.status { return true }; return false }.count }

    // MARK: - Actions

    func start(files: [(remotePath: String, name: String)],
               using transfer: any DigitaktTransferProtocol) {
        items    = files.map { Item(remotePath: $0.remotePath, name: $0.name) }
        isActive = true
        Task {
            for i in items.indices {
                await downloadItem(at: i, using: transfer)
            }
        }
    }

    func dismiss() {
        items    = []
        isActive = false
    }

    // MARK: - Private

    private func downloadItem(at index: Int, using transfer: any DigitaktTransferProtocol) async {
        items[index].status = .downloading(0)
        do {
            let url = try await transfer.downloadSample(remotePath: items[index].remotePath) { [weak self] prog in
                Task { @MainActor [weak self] in
                    guard let self, index < self.items.count,
                          case .downloading = self.items[index].status else { return }
                    self.items[index].status = .downloading(prog.fraction)
                }
            }
            items[index].status = .done(url)
        } catch {
            items[index].status = .failed(error.localizedDescription.uppercased())
        }
    }
}
