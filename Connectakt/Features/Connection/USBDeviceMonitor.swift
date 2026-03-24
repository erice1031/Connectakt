import CoreMIDI
import Foundation
import Observation

// MARK: - Elektron Device Info

struct ElektronDeviceInfo: Equatable {
    let name: String
    let source: MIDIEndpointRef
    let destination: MIDIEndpointRef

    // Digitakt VID 0x1935, PID 0x0b2c (Overbridge mode) or 0x000C (legacy)
    static let knownNames = ["Digitakt"]
}

// MARK: - USB / MIDI Device Monitor
//
// Watches CoreMIDI notifications to detect when an Elektron Digitakt is
// connected or disconnected via USB.
//
// USB MIDI is a class-compliant interface — no MFi, no entitlements required
// on iOS or macOS. The Digitakt appears automatically as a CoreMIDI source
// and destination named "Digitakt" when connected via USB.

@Observable
final class USBDeviceMonitor {

    private(set) var connectedDevice: ElektronDeviceInfo?

    /// Called on MainActor when a Digitakt is detected (fires once per connect).
    var onDeviceConnected: ((ElektronDeviceInfo) -> Void)?

    /// Called on MainActor when the previously detected Digitakt disappears.
    var onDeviceDisconnected: (() -> Void)?

    private var midiClient: MIDIClientRef = 0

    // MARK: - Start / Stop

    func start() {
        let block: MIDINotifyBlock = { [weak self] notification in
            switch notification.pointee.messageID {
            case .msgObjectAdded, .msgObjectRemoved, .msgSetupChanged:
                self?.scanDevices()
            default:
                break
            }
        }

        MIDIClientCreateWithBlock("ConnektaktMonitor" as CFString, &midiClient, block)
        scanDevices()
    }

    func stop() {
        if midiClient != 0 {
            MIDIClientDispose(midiClient)
            midiClient = 0
        }
    }

    // MARK: - Device Scan (called on notification thread → dispatches to main)

    func scanDevices() {
        let found = findElektronDevice()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let previous = self.connectedDevice
            self.connectedDevice = found

            if let found, previous == nil {
                self.onDeviceConnected?(found)
            } else if found == nil, previous != nil {
                self.onDeviceDisconnected?()
            }
        }
    }

    // MARK: - Discovery

    private func findElektronDevice() -> ElektronDeviceInfo? {
        let srcCount = MIDIGetNumberOfSources()
        let dstCount = MIDIGetNumberOfDestinations()

        for srcIdx in 0..<srcCount {
            let src = MIDIGetSource(srcIdx)
            guard let srcName = endpointDisplayName(src),
                  ElektronDeviceInfo.knownNames.contains(where: { srcName.contains($0) }) else { continue }

            for dstIdx in 0..<dstCount {
                let dst = MIDIGetDestination(dstIdx)
                if let dstName = endpointDisplayName(dst),
                   ElektronDeviceInfo.knownNames.contains(where: { dstName.contains($0) }) {
                    return ElektronDeviceInfo(name: srcName, source: src, destination: dst)
                }
            }
        }
        return nil
    }

    private func endpointDisplayName(_ endpoint: MIDIEndpointRef) -> String? {
        var property: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &property)
        return property?.takeRetainedValue() as String?
    }
}
