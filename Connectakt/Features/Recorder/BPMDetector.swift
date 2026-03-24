import Foundation

/// Rising-edge onset detector that estimates BPM from audio amplitude.
/// Thread-safe via NSLock — safe to call from the AVAudioEngine tap thread.
final class BPMDetector {

    private let lock = NSLock()
    private var onsetTimestamps: [Double] = []
    private var lastOnsetTime: Double = 0
    private var previousRMS: Float = 0

    private let threshold: Float = 0.15         // RMS level that counts as an onset
    private let minOnsetInterval: Double = 0.20  // 300 BPM ceiling
    private let minOnsets = 8                    // Need this many before estimating

    // MARK: - Feed

    /// Feed one RMS value + its timestamp.  Returns estimated BPM once enough
    /// onsets are collected, otherwise `nil`.
    @discardableResult
    func feed(rms: Float, timestamp: Double) -> Int? {
        lock.withLock {
            defer { previousRMS = rms }

            let isRisingEdge = rms > threshold
                && previousRMS <= threshold
                && (timestamp - lastOnsetTime) >= minOnsetInterval

            if isRisingEdge {
                onsetTimestamps.append(timestamp)
                lastOnsetTime = timestamp
                if onsetTimestamps.count > 16 { onsetTimestamps.removeFirst() }
            }

            guard onsetTimestamps.count >= minOnsets else { return nil }

            var total: Double = 0
            for i in 1..<onsetTimestamps.count {
                total += onsetTimestamps[i] - onsetTimestamps[i - 1]
            }
            let avgInterval = total / Double(onsetTimestamps.count - 1)
            guard avgInterval > 0 else { return nil }

            let bpm = Int((60.0 / avgInterval).rounded())
            return (20...300).contains(bpm) ? bpm : nil
        }
    }

    // MARK: - Reset

    func reset() {
        lock.withLock {
            onsetTimestamps.removeAll()
            lastOnsetTime = 0
            previousRMS = 0
        }
    }
}
