import Foundation

// MARK: - Snap Quantization

enum SnapQuantization: String, CaseIterable, Identifiable {
    case bar       = "BAR"
    case beat      = "BEAT"
    case half      = "1/2"
    case sixteenth = "1/4"

    var id: String { rawValue }
}

// MARK: - Bar/Beat Position

/// Elektron-style position display: "001.1.1"  (bar.beat.16th)
struct BarBeatPos: Equatable {
    let bar: Int        // 1-based
    let beat: Int       // 1-based, 1..4 in 4/4
    let sixteenth: Int  // 1-based, 1..4

    var displayString: String {
        String(format: "%03d.%d.%d", bar, beat, sixteenth)
    }

    var shortString: String {
        String(format: "%03d.%d", bar, beat)
    }
}

// MARK: - Musical Grid

struct MusicalGrid: Equatable {

    let bpm: Double
    let beatsPerBar: Int    // 4 for 4/4
    let beatPhase: Double   // seconds from file/recording start to beat 1

    init(bpm: Double, beatsPerBar: Int = 4, beatPhase: Double = 0) {
        self.bpm = max(bpm, 1)
        self.beatsPerBar = max(beatsPerBar, 1)
        self.beatPhase = beatPhase
    }

    // MARK: - Derived periods

    var secondsPerBeat: Double      { 60.0 / bpm }
    var secondsPerBar: Double       { secondsPerBeat * Double(beatsPerBar) }
    var secondsPerSixteenth: Double { secondsPerBeat / 4.0 }
    var secondsPerHalfBeat: Double  { secondsPerBeat / 2.0 }

    // MARK: - Position at time

    func barBeat(at seconds: Double) -> BarBeatPos {
        let rel = max(seconds - beatPhase, 0)
        let totalSixteenths = Int(rel / secondsPerSixteenth)
        let bar        = totalSixteenths / (beatsPerBar * 4) + 1
        let beat       = (totalSixteenths / 4) % beatsPerBar + 1
        let sixteenth  = totalSixteenths % 4 + 1
        return BarBeatPos(bar: bar, beat: beat, sixteenth: sixteenth)
    }

    // MARK: - Snapping

    func snapped(_ seconds: Double, to q: SnapQuantization) -> Double {
        let rel = seconds - beatPhase
        let period: Double
        switch q {
        case .bar:       period = secondsPerBar
        case .beat:      period = secondsPerBeat
        case .half:      period = secondsPerHalfBeat
        case .sixteenth: period = secondsPerSixteenth
        }
        return beatPhase + max((rel / period).rounded() * period, 0)
    }

    // MARK: - Grid line positions in a time range

    /// Beat timestamps (in seconds) within [start, end].
    func beatTimes(in range: ClosedRange<Double>) -> [Double] {
        gridTimes(period: secondsPerBeat, in: range)
    }

    /// Bar timestamps (in seconds) within [start, end].
    func barTimes(in range: ClosedRange<Double>) -> [Double] {
        gridTimes(period: secondsPerBar, in: range)
    }

    private func gridTimes(period: Double, in range: ClosedRange<Double>) -> [Double] {
        guard period > 0 else { return [] }
        let firstIndex = max(0, Int((range.lowerBound - beatPhase) / period))
        var out: [Double] = []
        var t = beatPhase + Double(firstIndex) * period
        while t <= range.upperBound + 1e-9 {
            if t >= range.lowerBound { out.append(t) }
            t += period
        }
        return out
    }

    // MARK: - Bar count for a duration

    func bars(for duration: Double) -> Int {
        max(1, Int(ceil((duration - beatPhase) / secondsPerBar)))
    }
}
