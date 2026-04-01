import CoreMIDI
import Foundation
import Observation

/// Listens on all CoreMIDI sources for MIDI clock pulses (0xF8 = 24 PPQN).
/// Derives BPM by averaging the inter-pulse intervals over a rolling window.
/// Thread-safe: pulse timestamps are accumulated on the MIDI thread; BPM is
/// published on the main actor.
@Observable
final class MIDIClockReceiver {

    private(set) var bpm: Double?    = nil
    private(set) var isActive: Bool  = false

    // MARK: - Private

    private var midiClient: MIDIClientRef = 0
    private var inputPort:  MIDIPortRef   = 0

    // Rolling pulse timestamps (wall clock, seconds)
    private var pulseTimestamps: [Double] = []
    private var lastPulseAt: Double = 0

    private let pulsesPerBeat = 24   // MIDI spec: 24 ppqn
    private let windowBeats   = 2    // average over 2 beats for stability
    private var windowPulses: Int { pulsesPerBeat * windowBeats + 1 }

    private var activityTask: Task<Void, Never>?

    // MARK: - Start / Stop

    func start() {
        guard midiClient == 0 else { return }

        let readBlock: MIDIReadBlock = { [weak self] packetList, _ in
            guard let self else { return }
            let n = Int(packetList.pointee.numPackets)
            withUnsafePointer(to: packetList.pointee.packet) { base in
                var pkt: UnsafePointer<MIDIPacket> = base
                for _ in 0..<n {
                    if pkt.pointee.length > 0 && pkt.pointee.data.0 == 0xF8 {
                        // MIDI timing clock pulse — record wall-clock timestamp
                        self.receivePulse(at: Date().timeIntervalSinceReferenceDate)
                    }
                    pkt = UnsafePointer(MIDIPacketNext(UnsafeMutablePointer(mutating: pkt)))
                }
            }
        }

        MIDIClientCreate("ConnektaktClock" as CFString, nil, nil, &midiClient)
        MIDIInputPortCreateWithBlock(midiClient, "ClockIn" as CFString, &inputPort, readBlock)

        // Connect to every source currently visible to CoreMIDI
        for i in 0..<MIDIGetNumberOfSources() {
            MIDIPortConnectSource(inputPort, MIDIGetSource(i), nil)
        }

        startActivityMonitor()
    }

    func stop() {
        activityTask?.cancel()
        activityTask = nil
        if midiClient != 0 { MIDIClientDispose(midiClient) }
        midiClient = 0
        inputPort  = 0
        pulseTimestamps.removeAll()
        bpm      = nil
        isActive = false
    }

    // MARK: - Pulse handling (called on MIDI thread)

    private func receivePulse(at t: Double) {
        pulseTimestamps.append(t)
        if pulseTimestamps.count > windowPulses { pulseTimestamps.removeFirst() }
        lastPulseAt = t

        guard pulseTimestamps.count >= pulsesPerBeat + 1 else { return }

        // Use the last `pulsesPerBeat` intervals for the estimate
        let window = pulseTimestamps.suffix(pulsesPerBeat + 1)
        let span   = window.last! - window.first!
        guard span > 0 else { return }

        // span covers exactly `pulsesPerBeat` pulse intervals → 1 quarter note
        let bpmEstimate = 60.0 / span
        guard (20.0...300.0).contains(bpmEstimate) else { return }

        Task { @MainActor [weak self] in
            self?.bpm      = bpmEstimate
            self?.isActive = true
        }
    }

    // MARK: - Activity watchdog

    private func startActivityMonitor() {
        activityTask?.cancel()
        activityTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self else { return }
                let now = Date().timeIntervalSinceReferenceDate
                if self.lastPulseAt > 0 && (now - self.lastPulseAt) > 1.0 {
                    await MainActor.run {
                        self.isActive = false
                        self.pulseTimestamps.removeAll()
                        // Keep last known BPM visible until replaced
                    }
                }
            }
        }
    }
}
