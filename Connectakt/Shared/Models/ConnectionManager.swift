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
    var totalStorageBytes: Int64 = 734_003_200  // ~700 MB

    var storagePercent: Double {
        guard totalStorageBytes > 0 else { return 0 }
        return Double(usedStorageBytes) / Double(totalStorageBytes)
    }

    var usedStorageMB: Int { Int(usedStorageBytes / 1_048_576) }
    var totalStorageMB: Int { Int(totalStorageBytes / 1_048_576) }

    // MARK: - Phase 2: Transfer Protocol

    /// Active transfer handler — MockDigitaktTransfer in dev, ElektronTransfer in production.
    var transfer: (any DigitaktTransferProtocol)?

    // MARK: - Phase 1: Development Simulation

    func simulateConnect() {
        status = .scanning
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            await MainActor.run {
                status = .connected(deviceName: "DIGITAKT")
                transfer = MockDigitaktTransfer()
                loadMockSamples()
            }
        }
    }

    func disconnect() {
        status = .disconnected
        samples = []
        usedStorageBytes = 0
        transfer = nil
    }

    // MARK: - Phase 3: USB Audio Detection

    func startUSBMonitoring() {
        #if os(iOS)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkUSBAudioInput()
        }
        checkUSBAudioInput()
        #endif
    }

    #if os(iOS)
    private func checkUSBAudioInput() {
        let session = AVAudioSession.sharedInstance()
        let usbInput = session.currentRoute.inputs.first { $0.portType == .usbAudio }
        if let input = usbInput {
            guard !status.isConnected else { return }
            let name = input.portName.isEmpty ? "DIGITAKT" : input.portName.uppercased()
            status = .connected(deviceName: name)
            transfer = MockDigitaktTransfer()
            loadMockSamples()
        } else if status.isConnected {
            disconnect()
        }
    }
    #endif

    /// Refresh sample list from device (mock for Phase 2)
    func refreshSamples() async {
        guard let transfer else { return }
        do {
            let remote = try await transfer.listFiles(remotePath: "SAMPLES/")
            samples = remote
            usedStorageBytes = remote.reduce(0) { $0 + $1.size }
        } catch { /* ignore in mock */ }
    }

    private func loadMockSamples() {
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
