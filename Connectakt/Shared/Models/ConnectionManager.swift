import Observation
import Foundation
#if os(iOS)
import AVFoundation
#endif

// MARK: - Connection State

enum ConnectionStatus: Equatable {
    case disconnected
    case scanning
    case connected(deviceName: String)

    var label: String {
        switch self {
        case .disconnected:           return "NO DEVICE"
        case .scanning:               return "SCANNING..."
        case .connected(let name):    return name.uppercased()
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

// MARK: - Sample File Model

struct SampleFile: Identifiable, Equatable {
    let id: UUID = UUID()
    let name: String
    let size: Int64    // bytes
    let isFolder: Bool
    let itemType: UInt8   // raw item_type byte from device listing (debug)

    init(name: String, size: Int64, isFolder: Bool, itemType: UInt8 = 0) {
        self.name = name
        self.size = size
        self.isFolder = isFolder
        self.itemType = itemType
    }

    var sizeString: String {
        let mb = Double(size) / 1_048_576
        if mb < 1 { return String(format: "%.0f KB", Double(size) / 1024) }
        return String(format: "%.1f MB", mb)
    }
}

// MARK: - Connection Manager

@Observable
final class ConnectionManager {

    var status: ConnectionStatus = .disconnected
    var samples: [SampleFile] = []
    var usedStorageBytes: Int64 = 0
    var totalStorageBytes: Int64 = 0

    /// Last folder the user browsed to — used as the default upload destination in Recorder.
    var lastBrowsedPath: String = "/"

    var storagePercent: Double {
        guard totalStorageBytes > 0 else { return 0 }
        return Double(usedStorageBytes) / Double(totalStorageBytes)
    }

    var usedStorageMB: Int { Int(usedStorageBytes / 1_048_576) }
    var totalStorageMB: Int { Int(totalStorageBytes / 1_048_576) }

    // MARK: - Transfer

    /// Active transfer handler. MockDigitaktTransfer in sim, ElektronMIDITransfer on hardware.
    var transfer: (any DigitaktTransferProtocol)?

    /// Set to open a downloaded file directly in the Editor tab.
    var pendingEditorURL: URL?

    /// Human-readable label of the active transfer backend (for diagnostics).
    private(set) var transferLabel: String = "—"

    /// True while a sample listing is in flight.
    private(set) var isLoadingSamples = false

    /// Non-nil when the last sample listing failed.
    private(set) var sampleLoadError: String? = nil

    // MARK: - USB / MIDI Monitor (Phase 3)

    private let usbMonitor = USBDeviceMonitor()

    /// Persistent MIDI diagnostic monitor — survives tab switches.
    let midiMonitor = MIDIMonitor()

    func startUSBMonitoring() {
        midiMonitor.start()

        // MIDI-based detection (iOS + macOS, no entitlements required)
        usbMonitor.onDeviceConnected = { [weak self] device in
            self?.connectMIDIDevice(device)
        }
        usbMonitor.onDeviceDisconnected = { [weak self] in
            self?.disconnect()
        }
        usbMonitor.start()

        // iOS: also watch USB audio route for recording enablement
        #if os(iOS)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkUSBAudioRoute()
        }
        checkUSBAudioRoute()
        #endif
    }

    // MARK: - MIDI Device Connection

    private func connectMIDIDevice(_ device: ElektronDeviceInfo) {
        status = .connected(deviceName: device.name.uppercased())
        if let midi = try? ElektronMIDITransfer(device: device) {
            transfer = midi
            transferLabel = "MIDI SYSEX"
        } else {
            transfer = MockDigitaktTransfer()
            transferLabel = "SIMULATION"
        }
        Task { await refreshSamples() }
    }

    // MARK: - iOS Audio Route Check

    #if os(iOS)
    private func checkUSBAudioRoute() {
        let session = AVAudioSession.sharedInstance()
        let usbAudio = session.currentRoute.inputs.first { $0.portType == .usbAudio }
        // Only update connection if MIDI monitor hasn't already connected us
        if usbAudio != nil, !status.isConnected {
            let name = usbAudio!.portName.isEmpty ? "DIGITAKT" : usbAudio!.portName.uppercased()
            status = .connected(deviceName: name)
            transfer = MockDigitaktTransfer()
            loadMockSamples()
        }
    }
    #endif

    // MARK: - Disconnect

    func disconnect() {
        status = .disconnected
        samples = []
        usedStorageBytes = 0
        lastBrowsedPath = "/"
        transfer = nil
        transferLabel = "—"
        isLoadingSamples = false
        sampleLoadError = nil
    }

    // MARK: - Development Simulation

    func simulateConnect() {
        status = .scanning
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            await MainActor.run {
                self.status = .connected(deviceName: "DIGITAKT")
                self.transfer = MockDigitaktTransfer()
                self.loadMockSamples()
            }
        }
    }

    // MARK: - Sample Refresh

    func refreshSamples(path: String = "/") async {
        guard let transfer else { return }
        isLoadingSamples = true
        sampleLoadError  = nil
        do {
            let remote = try await transfer.listFiles(remotePath: path)
            samples         = remote
            sampleLoadError = nil
            if let info = try? await transfer.getStorageInfo() {
                usedStorageBytes  = info.usedBytes
                totalStorageBytes = info.totalBytes
            } else {
                // Digitakt doesn't expose storage stats via SysEx — use known 1 GB capacity
                // so the storage meter is visible. Estimate usage from file listing.
                usedStorageBytes  = remote.reduce(0) { $0 + $1.size }
                totalStorageBytes = 1_000_000_000
            }
        } catch {
            sampleLoadError = error.localizedDescription
        }
        isLoadingSamples = false
    }

    func deleteFile(at path: String) async {
        guard let transfer else { return }
        do {
            try await transfer.deleteFile(remotePath: path)
            let filename = URL(fileURLWithPath: path).lastPathComponent
            samples.removeAll { $0.name == filename }
        } catch {
            sampleLoadError = error.localizedDescription
        }
    }

    func loadMockSamples() {
        samples = [
            SampleFile(name: "KICK_01.WAV",        size: 2_412_544, isFolder: false),
            SampleFile(name: "KICK_DEEP.WAV",       size: 1_835_008, isFolder: false),
            SampleFile(name: "SNARE_DRY.WAV",       size: 1_153_433, isFolder: false),
            SampleFile(name: "SNARE_VERB.WAV",      size: 2_097_152, isFolder: false),
            SampleFile(name: "HH_CLOSED.WAV",       size: 838_860,   isFolder: false),
            SampleFile(name: "HH_OPEN.WAV",         size: 1_258_291, isFolder: false),
            SampleFile(name: "CLAP_ROOM.WAV",       size: 943_718,   isFolder: false),
            SampleFile(name: "BASS_LOOP_120.WAV",   size: 3_354_394, isFolder: false),
            SampleFile(name: "PERC_SHAKER.WAV",     size: 419_430,   isFolder: false),
            SampleFile(name: "SYNTH_STAB.WAV",      size: 786_432,   isFolder: false),
            SampleFile(name: "VOCAL_CHOP_01.WAV",   size: 1_572_864, isFolder: false),
            SampleFile(name: "FX_RISER.WAV",        size: 2_621_440, isFolder: false),
        ]
        usedStorageBytes = samples.reduce(0) { $0 + $1.size }
    }
}
