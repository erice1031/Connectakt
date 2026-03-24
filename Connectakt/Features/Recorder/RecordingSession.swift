import Foundation

struct RecordingSession: Identifiable, Codable, Equatable {
    let id: UUID
    let fileURL: URL
    let displayName: String
    let durationSeconds: Double
    let bpm: Int?
    let createdAt: Date
    let fileSizeBytes: Int64

    init(
        fileURL: URL,
        durationSeconds: Double,
        bpm: Int? = nil,
        fileSizeBytes: Int64 = 0
    ) {
        self.id = UUID()
        self.fileURL = fileURL
        self.durationSeconds = durationSeconds
        self.bpm = bpm
        self.fileSizeBytes = fileSizeBytes
        self.createdAt = Date()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let stamp = formatter.string(from: createdAt)
        self.displayName = bpm.map { "REC_\(stamp)_\($0)BPM" } ?? "REC_\(stamp)"
    }

    // MARK: - Formatting

    var durationString: String {
        let m = Int(durationSeconds) / 60
        let s = Int(durationSeconds) % 60
        return String(format: "%02d:%02d", m, s)
    }

    var sizeString: String {
        let mb = Double(fileSizeBytes) / 1_048_576
        if mb < 1 { return String(format: "%.0f KB", Double(fileSizeBytes) / 1024) }
        return String(format: "%.1f MB", mb)
    }
}
