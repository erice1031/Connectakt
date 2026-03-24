import Testing
import Foundation
@testable import Connectakt

// MARK: - BPMDetector Tests

@Suite("BPMDetector")
struct BPMDetectorTests {

    @Test("No result returned before minimum onsets collected")
    func noResultBeforeThreshold() {
        let detector = BPMDetector()
        var result: Int? = nil
        // Feed 7 onsets (need 8) — interleave with silence to generate rising edges
        for i in 0..<7 {
            _ = detector.feed(rms: 0.0,  timestamp: Double(i) * 0.5)
            result = detector.feed(rms: 0.8, timestamp: Double(i) * 0.5 + 0.05)
        }
        #expect(result == nil)
    }

    @Test("Returns BPM near 120 after sufficient onsets at 120 BPM cadence")
    func detects120BPM() {
        let detector = BPMDetector()
        let interval = 60.0 / 120.0   // 0.5 s between beats
        var lastResult: Int? = nil
        for i in 0..<12 {
            // Silence before each beat (ensures rising edge)
            _ = detector.feed(rms: 0.0,  timestamp: Double(i) * interval - 0.05)
            lastResult = detector.feed(rms: 0.8, timestamp: Double(i) * interval)
        }
        #expect(lastResult != nil)
        if let bpm = lastResult {
            #expect(abs(bpm - 120) <= 5)
        }
    }

    @Test("Reset clears accumulated onsets")
    func resetClearsState() {
        let detector = BPMDetector()
        let interval = 60.0 / 120.0
        for i in 0..<12 {
            _ = detector.feed(rms: 0.0,  timestamp: Double(i) * interval - 0.05)
            _ = detector.feed(rms: 0.8,  timestamp: Double(i) * interval)
        }
        detector.reset()
        // After reset, a single onset should not produce a BPM result
        let result = detector.feed(rms: 0.8, timestamp: 100.0)
        #expect(result == nil)
    }

    @Test("Values outside 20–300 BPM range are rejected")
    func rejectsOutOfRangeBPM() {
        let detector = BPMDetector()
        // Space beats at 3 s = 20 BPM boundary — use 4 s to go below 20 BPM
        var lastResult: Int? = nil
        for i in 0..<12 {
            _ = detector.feed(rms: 0.0,  timestamp: Double(i) * 4.0 - 0.05)
            lastResult = detector.feed(rms: 0.8, timestamp: Double(i) * 4.0)
        }
        // 4 s interval → 15 BPM — should be rejected (nil or not in range)
        if let bpm = lastResult {
            #expect(!(20...300).contains(bpm) == false)  // if returned, must be in range
        }
    }
}

// MARK: - RecordingSession Tests

@Suite("RecordingSession")
struct RecordingSessionTests {

    @Test("DisplayName includes BPM suffix when BPM is provided")
    func displayNameWithBPM() {
        let session = RecordingSession(
            fileURL: URL(fileURLWithPath: "/tmp/test.caf"),
            durationSeconds: 10.0,
            bpm: 128
        )
        #expect(session.displayName.hasPrefix("REC_"))
        #expect(session.displayName.contains("128BPM"))
    }

    @Test("DisplayName has no BPM suffix when BPM is nil")
    func displayNameWithoutBPM() {
        let session = RecordingSession(
            fileURL: URL(fileURLWithPath: "/tmp/test.caf"),
            durationSeconds: 5.0,
            bpm: nil
        )
        #expect(session.displayName.hasPrefix("REC_"))
        #expect(!session.displayName.contains("BPM"))
    }

    @Test("DurationString formats mm:ss correctly")
    func durationString() {
        let session = RecordingSession(
            fileURL: URL(fileURLWithPath: "/tmp/test.caf"),
            durationSeconds: 75.5
        )
        #expect(session.durationString == "01:15")
    }

    @Test("SizeString shows KB for files under 1 MB")
    func sizeStringKB() {
        let session = RecordingSession(
            fileURL: URL(fileURLWithPath: "/tmp/test.caf"),
            durationSeconds: 1.0,
            fileSizeBytes: 512_000
        )
        #expect(session.sizeString.contains("KB"))
    }

    @Test("SizeString shows MB for files 1 MB and over")
    func sizeStringMB() {
        let session = RecordingSession(
            fileURL: URL(fileURLWithPath: "/tmp/test.caf"),
            durationSeconds: 1.0,
            fileSizeBytes: 2_097_152
        )
        #expect(session.sizeString.contains("MB"))
    }

    @Test("RecordingSession round-trips through JSON codec")
    func codable() throws {
        let session = RecordingSession(
            fileURL: URL(fileURLWithPath: "/tmp/test.caf"),
            durationSeconds: 30.0,
            bpm: 140,
            fileSizeBytes: 1_000_000
        )
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(RecordingSession.self, from: data)
        #expect(decoded.id          == session.id)
        #expect(decoded.bpm         == 140)
        #expect(decoded.displayName == session.displayName)
        #expect(decoded.fileSizeBytes == 1_000_000)
    }
}

// MARK: - RecordingHistoryManager Tests

@Suite("RecordingHistoryManager")
struct RecordingHistoryManagerTests {

    @Test("Adding a session inserts it at the front of the list")
    func addSession() {
        let manager = RecordingHistoryManager()
        let session = RecordingSession(
            fileURL: URL(fileURLWithPath: "/tmp/ck_add_\(UUID().uuidString).caf"),
            durationSeconds: 10.0
        )
        manager.add(session)
        #expect(manager.sessions.first?.id == session.id)
    }

    @Test("Most recently added session appears first")
    func newestFirst() {
        let manager = RecordingHistoryManager()
        let s1 = RecordingSession(fileURL: URL(fileURLWithPath: "/tmp/ck_s1.caf"), durationSeconds: 1.0)
        let s2 = RecordingSession(fileURL: URL(fileURLWithPath: "/tmp/ck_s2.caf"), durationSeconds: 2.0)
        manager.add(s1)
        manager.add(s2)
        #expect(manager.sessions.first?.id == s2.id)
    }

    @Test("Session list is capped at 20 entries")
    func cappedAt20() {
        let manager = RecordingHistoryManager()
        for i in 0..<25 {
            let url = URL(fileURLWithPath: "/tmp/ck_cap_\(i)_\(UUID().uuidString).caf")
            manager.add(RecordingSession(fileURL: url, durationSeconds: Double(i)))
        }
        #expect(manager.sessions.count <= 20)
    }

    @Test("Removing by ID deletes the correct session")
    func removeByID() {
        let manager = RecordingHistoryManager()
        let s1 = RecordingSession(fileURL: URL(fileURLWithPath: "/tmp/ck_r1.caf"), durationSeconds: 1.0)
        let s2 = RecordingSession(fileURL: URL(fileURLWithPath: "/tmp/ck_r2.caf"), durationSeconds: 2.0)
        manager.add(s1)
        manager.add(s2)
        manager.remove(id: s1.id)
        #expect(!manager.sessions.contains(where: { $0.id == s1.id }))
        #expect(manager.sessions.contains(where: { $0.id == s2.id }))
    }
}
