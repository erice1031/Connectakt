import Foundation

struct RecordingSession: Identifiable, Codable, Equatable {
    let id:              UUID
    let fileURL:         URL
    let displayName:     String
    let durationSeconds: Double
    let bpm:             Int?
    let beatPhase:       Double?   // seconds to first beat; nil = unknown
    let createdAt:       Date
    let fileSizeBytes:   Int64

    init(
        fileURL:         URL,
        durationSeconds: Double,
        bpm:             Int?    = nil,
        beatPhase:       Double? = nil,
        fileSizeBytes:   Int64  = 0
    ) {
        self.id              = UUID()
        self.fileURL         = fileURL
        self.durationSeconds = durationSeconds
        self.bpm             = bpm
        self.beatPhase       = beatPhase
        self.fileSizeBytes   = fileSizeBytes
        self.createdAt       = Date()

        let formatter        = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let stamp            = formatter.string(from: createdAt)
        self.displayName     = bpm.map { "REC_\(stamp)_\($0)BPM" } ?? "REC_\(stamp)"
    }

    // MARK: - Codable (beatPhase is optional for backwards compat with older JSON)

    enum CodingKeys: String, CodingKey {
        case id, fileURL, displayName, durationSeconds, bpm, beatPhase, createdAt, fileSizeBytes
    }

    init(from decoder: Decoder) throws {
        let c            = try decoder.container(keyedBy: CodingKeys.self)
        id               = try c.decode(UUID.self,   forKey: .id)
        fileURL          = try c.decode(URL.self,    forKey: .fileURL)
        displayName      = try c.decode(String.self, forKey: .displayName)
        durationSeconds  = try c.decode(Double.self, forKey: .durationSeconds)
        bpm              = try c.decodeIfPresent(Int.self,    forKey: .bpm)
        beatPhase        = try c.decodeIfPresent(Double.self, forKey: .beatPhase)
        createdAt        = try c.decode(Date.self,   forKey: .createdAt)
        fileSizeBytes    = try c.decode(Int64.self,  forKey: .fileSizeBytes)
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

    /// A MusicalGrid if BPM is known.
    var musicalGrid: MusicalGrid? {
        guard let bpm else { return nil }
        return MusicalGrid(bpm: Double(bpm), beatPhase: beatPhase ?? 0)
    }
}
