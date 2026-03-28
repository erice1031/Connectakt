#if os(macOS)
import Foundation
import IOKit
import IOUSBHost

// MARK: - IOUSBHostTransport (macOS only)
//
// Low-level USB bulk transport to the Digitakt's vendor-specific interface.
//
// The Digitakt is a USB composite device with multiple interfaces:
//   ├── Audio control + streaming  (bInterfaceClass 0x01, claimed by IOUSBAudioFamily)
//   ├── MIDI class-compliant       (bInterfaceClass 0x01/0x03, claimed by IOUSBMIDIDriver)
//   └── Vendor-specific transfer   (bInterfaceClass 0xFF) ← this class
//
// Elektron Transfer protocol messages — the same SysEx framing used over MIDI (F0…F7
// with nibble encoding) — are sent directly over the bulk IN/OUT endpoints of the
// vendor-specific interface. No MIDI protocol overhead. Verified against the
// Elektroid open-source implementation (https://github.com/dagargo/elektroid).
//
// Entitlement required: com.apple.security.device.usb

final class IOUSBHostTransport {

    static let elektronVID = 0x1935  // Elektron Music Machines USB Vendor ID

    private var usbInterface: IOUSBHostInterface?
    private var bulkOut: IOUSBHostPipe?
    private var bulkIn:  IOUSBHostPipe?

    var isOpen: Bool { usbInterface != nil }

    // MARK: - Open / Close

    /// Locates the Digitakt by USB Vendor ID, opens its vendor-specific interface,
    /// and captures the bulk IN/OUT endpoint pipes.
    ///
    /// Uses `IOUSBHostInterface.createMatchingDictionary` to find the correct service,
    /// then iterates endpoint descriptors via `IOUSBGetNextEndpointDescriptor`.
    ///
    /// Call from a background thread — IOKit enumeration is synchronous.
    func open() throws {
        // Build IOKit matching dictionary for Elektron VID + vendor-specific class 0xFF
        var matching = IOServiceMatching("IOUSBHostInterface") as! [String: Any]
        matching["idVendor"]        = Self.elektronVID
        matching["bInterfaceClass"] = 0xFF   // Vendor Specific

        var iterator: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching as CFDictionary, &iterator)
        guard kr == kIOReturnSuccess else { throw USBTransportError.deviceNotFound }
        defer { IOObjectRelease(iterator) }

        // Open the first matching interface (typically only one on Digitakt)
        var foundIface: IOUSBHostInterface? = nil
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let iface = try? IOUSBHostInterface(
                __ioService: service, options: [], queue: nil, interestHandler: nil
            ) {
                foundIface = iface
                IOObjectRelease(service)
                break
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        guard let iface = foundIface else { throw USBTransportError.interfaceNotFound }
        usbInterface = iface

        // Iterate endpoint descriptors to locate bulk IN and OUT addresses.
        // IOUSBGetNextEndpointDescriptor needs both the config and interface descriptors.
        let configDesc = iface.configurationDescriptor
        let ifaceDesc  = iface.interfaceDescriptor

        var inAddr:  UInt8? = nil
        var outAddr: UInt8? = nil

        var epPtr: UnsafePointer<IOUSBEndpointDescriptor>? = IOUSBGetNextEndpointDescriptor(configDesc, ifaceDesc, nil)
        while let ep = epPtr {
            let transferType = ep.pointee.bmAttributes & 0x03   // 0x02 = Bulk
            let address      = ep.pointee.bEndpointAddress
            if transferType == 0x02 {
                if address & 0x80 != 0 { inAddr  = address }   // IN:  D7 = 1
                else                   { outAddr = address }   // OUT: D7 = 0
            }
            // Advance to next endpoint within this interface
            let hdr = UnsafeRawPointer(ep).assumingMemoryBound(to: IOUSBDescriptorHeader.self)
            epPtr = IOUSBGetNextEndpointDescriptor(configDesc, ifaceDesc, hdr)
        }

        guard let inA = inAddr, let outA = outAddr else { throw USBTransportError.pipeNotFound }
        bulkOut = try iface.copyPipe(withAddress: Int(outA))
        bulkIn  = try iface.copyPipe(withAddress: Int(inA))
    }

    func close() {
        bulkOut      = nil
        bulkIn       = nil
        usbInterface = nil
    }

    // MARK: - Raw Bulk Transfer

    /// Sends `data` to the device's bulk OUT endpoint. Timeout: 5 seconds.
    func send(_ data: Data) throws {
        guard let pipe = bulkOut else { throw USBTransportError.notOpen }
        let mutableData = NSMutableData(data: data)
        try pipe.__sendIORequest(with: mutableData, bytesTransferred: nil, completionTimeout: 5.0)
    }

    /// Reads up to `maxLength` bytes from the device's bulk IN endpoint.
    /// Blocks until data arrives or `timeout` seconds elapse.
    func receive(maxLength: Int = 65_536, timeout: TimeInterval = 2.0) throws -> Data {
        guard let pipe = bulkIn else { throw USBTransportError.notOpen }
        let buffer = NSMutableData(length: maxLength)!
        var bytesReceived: Int = 0
        try pipe.__sendIORequest(with: buffer, bytesTransferred: &bytesReceived, completionTimeout: timeout)
        return Data(bytes: buffer.bytes, count: bytesReceived)
    }

    // MARK: - Errors

    enum USBTransportError: LocalizedError, Equatable {
        case deviceNotFound
        case interfaceNotFound
        case pipeNotFound
        case notOpen

        var errorDescription: String? {
            switch self {
            case .deviceNotFound:    return "DIGITAKT NOT FOUND — CONNECT USB AND TRY AGAIN"
            case .interfaceNotFound: return "TRANSFER INTERFACE UNAVAILABLE — RECONNECT USB"
            case .pipeNotFound:      return "USB ENDPOINTS NOT FOUND — UNSUPPORTED FIRMWARE?"
            case .notOpen:           return "USB TRANSPORT NOT OPEN"
            }
        }
    }
}
#endif
