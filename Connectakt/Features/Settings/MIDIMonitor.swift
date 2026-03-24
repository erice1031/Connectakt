import CoreMIDI
import Foundation
import Observation

// MARK: - Models

struct MIDIEndpointInfo: Identifiable, Equatable {
    let id = UUID()
    let ref: MIDIEndpointRef
    let name: String
    let isSource: Bool

    var isElektron: Bool {
        let lower = name.lowercased()
        return lower.contains("elektron") || lower.contains("digitakt")
    }

    var badge: String { isElektron ? "★" : "○" }
}

struct MIDILogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let direction: Direction
    let bytes: [UInt8]

    enum Direction { case tx, rx }

    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: timestamp)
    }

    var directionLabel: String { direction == .tx ? "TX→" : "RX←" }

    var hexString: String {
        let preview = bytes.prefix(48).map { String(format: "%02X", $0) }.joined(separator: " ")
        return bytes.count > 48 ? preview + " …(\(bytes.count)B)" : preview
    }

    var isSysEx: Bool { bytes.first == 0xF0 }

    var parsedDescription: String {
        guard isSysEx,
              bytes.count >= 6,
              bytes[1] == 0x00, bytes[2] == 0x20, bytes[3] == 0x3C else {
            return "NON-ELEKTRON MIDI"
        }
        let deviceID = bytes[4]
        let msgByte  = bytes[5]
        let msgType  = ElektronMsgType(rawValue: msgByte)
        let typeStr  = msgType.map { "\($0)" } ?? String(format: "0x%02X (UNKNOWN)", msgByte)
        return String(format: "ELEKTRON SYSEX  DEV=0x%02X  TYPE=%@  LEN=%d", deviceID, typeStr, bytes.count)
    }
}

// MARK: - MIDIMonitor

/// Diagnostic tool: enumerates all CoreMIDI endpoints and captures all MIDI traffic.
/// Self-contained — creates its own client so it doesn't interfere with ElektronMIDITransfer.
@Observable
final class MIDIMonitor {

    private(set) var sources:      [MIDIEndpointInfo] = []
    private(set) var destinations: [MIDIEndpointInfo] = []
    private(set) var log:          [MIDILogEntry] = []
    private(set) var isRunning = false

    private var midiClient: MIDIClientRef = 0
    private var inputPort:  MIDIPortRef   = 0
    private var outputPort: MIDIPortRef   = 0

    let maxLogEntries = 200
    var isPaused = false

    // MARK: - Start / Stop

    func start() {
        guard !isRunning else { return }

        let readBlock: MIDIReadBlock = { [weak self] packetList, _ in
            guard let self else { return }
            let count = Int(packetList.pointee.numPackets)
            withUnsafePointer(to: packetList.pointee.packet) { ptr in
                var pkt: UnsafePointer<MIDIPacket> = ptr
                for _ in 0..<count {
                    let len = Int(pkt.pointee.length)
                    if len > 0 {
                        let data = withUnsafePointer(to: pkt.pointee.data) { raw in
                            [UInt8](UnsafeRawBufferPointer(start: raw, count: len))
                        }
                        Task { await self.appendLog(.rx, bytes: data) }
                    }
                    pkt = UnsafePointer(MIDIPacketNext(UnsafeMutablePointer(mutating: pkt)))
                }
            }
        }

        MIDIClientCreate("ConnektaktDiag" as CFString, nil, nil, &midiClient)
        MIDIOutputPortCreate(midiClient, "DiagOut" as CFString, &outputPort)
        MIDIInputPortCreateWithBlock(midiClient, "DiagIn" as CFString, &inputPort, readBlock)

        isRunning = true
        refresh()
    }

    func stop() {
        if midiClient != 0 { MIDIClientDispose(midiClient) }
        midiClient = 0; inputPort = 0; outputPort = 0
        isRunning = false
    }

    // MARK: - Endpoint Refresh

    func refresh() {
        var newSources      = [MIDIEndpointInfo]()
        var newDestinations = [MIDIEndpointInfo]()

        for i in 0..<MIDIGetNumberOfSources() {
            let ref = MIDIGetSource(i)
            if let name = endpointName(ref) {
                newSources.append(MIDIEndpointInfo(ref: ref, name: name, isSource: true))
                // Connect input port to every source so we capture all traffic
                MIDIPortConnectSource(inputPort, ref, nil)
            }
        }

        for i in 0..<MIDIGetNumberOfDestinations() {
            let ref = MIDIGetDestination(i)
            if let name = endpointName(ref) {
                newDestinations.append(MIDIEndpointInfo(ref: ref, name: name, isSource: false))
            }
        }

        DispatchQueue.main.async {
            self.sources      = newSources
            self.destinations = newDestinations
        }
    }

    func clearLog() { log.removeAll() }

    // MARK: - Test Commands

    /// Sends an Elektron Device Info request to the given destination.
    func sendDeviceInfoRequest(to destination: MIDIEndpointRef) {
        sendSysEx(ElektronSysEx.build(msgType: .deviceInfoReq), to: destination)
    }

    /// Sends an Elektron Storage Info request to the given destination.
    func sendStorageInfoRequest(to destination: MIDIEndpointRef) {
        sendSysEx(ElektronSysEx.build(msgType: .storageInfoReq), to: destination)
    }

    /// Sends a List Directory request for "SAMPLES/" to the given destination.
    func sendListRequest(to destination: MIDIEndpointRef) {
        let payload = [UInt8].asciiString("SAMPLES/")
        sendSysEx(ElektronSysEx.build(msgType: .listDirReq, payload: payload), to: destination)
    }

    // MARK: - Private

    @MainActor
    private func appendLog(_ direction: MIDILogEntry.Direction, bytes: [UInt8]) {
        guard !isPaused else { return }
        let entry = MIDILogEntry(timestamp: Date(), direction: direction, bytes: bytes)
        log.append(entry)                          // newest at bottom (terminal style)
        if log.count > maxLogEntries { log.removeFirst() }
    }

    private func sendSysEx(_ bytes: [UInt8], to destination: MIDIEndpointRef) {
        var b = bytes
        let ptr = UnsafeMutablePointer<MIDIPacketList>.allocate(capacity: 1)
        defer { ptr.deallocate() }
        var pkt = MIDIPacketListInit(ptr)
        pkt = MIDIPacketListAdd(ptr, 65536, pkt, 0, b.count, &b)
        MIDISend(outputPort, destination, ptr)
        Task { await appendLog(.tx, bytes: bytes) }
    }

    private func endpointName(_ endpoint: MIDIEndpointRef) -> String? {
        var prop: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &prop)
        return prop?.takeRetainedValue() as String?
    }
}
