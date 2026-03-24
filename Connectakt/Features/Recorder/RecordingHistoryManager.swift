import Foundation
import Observation

@Observable
final class RecordingHistoryManager {

    private(set) var sessions: [RecordingSession] = []

    private let maxSessions = 20
    private let storageURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("ck_recording_history.json")
    }()

    init() {
        load()
    }

    // MARK: - Mutations

    func add(_ session: RecordingSession) {
        sessions.insert(session, at: 0)
        if sessions.count > maxSessions {
            let removed = sessions.removeLast()
            try? FileManager.default.removeItem(at: removed.fileURL)
        }
        save()
    }

    func remove(at offsets: IndexSet) {
        for index in offsets {
            try? FileManager.default.removeItem(at: sessions[index].fileURL)
        }
        sessions.remove(atOffsets: offsets)
        save()
    }

    func remove(id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(at: sessions[index].fileURL)
        sessions.remove(at: index)
        save()
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([RecordingSession].self, from: data) else {
            return
        }
        // Filter to sessions whose files still exist
        sessions = decoded.filter {
            FileManager.default.fileExists(atPath: $0.fileURL.path)
        }
    }
}
