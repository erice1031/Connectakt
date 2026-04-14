#!/usr/bin/swift
// usb_probe.swift — Elektron Digitakt USB interface scanner
// Usage: swift usb_probe.swift
// Requires macOS 14+, IOUSBHost.framework

import Foundation
import IOKit
import IOKit.usb
import IOUSBHost

let elektronVID = 0x1935

print("=== DIGITAKT USB PROBE ===\n")

// ── 1. Find all IOUSBHostInterface services for Elektron VID ──────────────────

var allMatching: [String: Any] = IOServiceMatching("IOUSBHostInterface") as! [String: Any]
allMatching["idVendor"] = elektronVID

var allIterator: io_iterator_t = 0
var kr = IOServiceGetMatchingServices(kIOMainPortDefault, allMatching as CFDictionary, &allIterator)

if kr != kIOReturnSuccess {
    print("IOServiceGetMatchingServices failed: \(String(format: "0x%08X", kr))")
    exit(1)
}

var found = 0
var service = IOIteratorNext(allIterator)
while service != 0 {
    found += 1

    // Read registry properties for this interface
    var props: Unmanaged<CFMutableDictionary>?
    IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0)
    let dict = props?.takeRetainedValue() as? [String: Any] ?? [:]

    let ifClass    = dict["bInterfaceClass"]    as? Int ?? -1
    let ifSubclass = dict["bInterfaceSubClass"] as? Int ?? -1
    let ifProtocol = dict["bInterfaceProtocol"] as? Int ?? -1
    let ifNumber   = dict["bInterfaceNumber"]   as? Int ?? -1
    let pid        = dict["idProduct"]          as? Int ?? -1

    print(String(format: "Interface #%d", ifNumber))
    print(String(format: "  PID:       0x%04X", pid))
    print(String(format: "  Class:     0x%02X  (%@)", ifClass,    classLabel(ifClass)))
    print(String(format: "  Subclass:  0x%02X", ifSubclass))
    print(String(format: "  Protocol:  0x%02X", ifProtocol))

    // Try opening this interface
    if ifClass == 0xFF {
        print("  → Vendor-specific interface found — attempting to open...")
        if let iface = try? IOUSBHostInterface(
            __ioService: service, options: [], queue: nil, interestHandler: nil
        ) {
            print("  ✓ OPENED SUCCESSFULLY")

            // Find bulk endpoints
            let configDesc = iface.configurationDescriptor
            let ifaceDesc  = iface.interfaceDescriptor
            var inAddr: UInt8? = nil
            var outAddr: UInt8? = nil

            var epPtr = IOUSBGetNextEndpointDescriptor(configDesc, ifaceDesc, nil)
            while let ep = epPtr {
                let type    = ep.pointee.bmAttributes & 0x03
                let address = ep.pointee.bEndpointAddress
                let maxPkt  = ep.pointee.wMaxPacketSize
                print(String(format: "    Endpoint 0x%02X  type=%@  maxPacket=%d",
                      address, epTypeLabel(type), maxPkt))
                if type == 0x02 {
                    if address & 0x80 != 0 { inAddr  = address }
                    else                   { outAddr = address }
                }
                let hdr = UnsafeRawPointer(ep).assumingMemoryBound(to: IOUSBDescriptorHeader.self)
                epPtr = IOUSBGetNextEndpointDescriptor(configDesc, ifaceDesc, hdr)
            }

            if let inA = inAddr, let outA = outAddr {
                print(String(format: "  ✓ Bulk OUT: 0x%02X  Bulk IN: 0x%02X", outA, inA))
                print("  ✓ TRANSPORT READY — USB bulk path should work")
            } else {
                print("  ✗ Could not locate bulk IN/OUT endpoints")
            }
        } else {
            print("  ✗ OPEN FAILED (kext may have claimed it, or entitlement missing)")
        }
    }

    print("")
    IOObjectRelease(service)
    service = IOIteratorNext(allIterator)
}
IOObjectRelease(allIterator)

if found == 0 {
    print("No IOUSBHostInterface services found for VID 0x1935.")
    print("Check: is the Digitakt powered on and connected via USB?")
} else {
    print("Total interfaces found: \(found)")
}

// ── Helpers ──────────────────────────────────────────────────────────────────

func classLabel(_ c: Int) -> String {
    switch c {
    case 0x01: return "Audio"
    case 0x03: return "HID"
    case 0xFF: return "Vendor-Specific ← transfer interface"
    default:   return "Other"
    }
}

func epTypeLabel(_ t: UInt8) -> String {
    switch t {
    case 0x00: return "Control"
    case 0x01: return "Isochronous"
    case 0x02: return "Bulk"
    case 0x03: return "Interrupt"
    default:   return "Unknown"
    }
}
