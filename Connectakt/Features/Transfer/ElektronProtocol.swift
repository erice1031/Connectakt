import Foundation

// MARK: - Elektron SysEx Protocol
//
// Elektron Digitakt communicates over USB MIDI (class-compliant, no MFi required).
// All file-management commands use System Exclusive (SysEx) messages.
//
// Reference: Elektroid open-source project (https://github.com/dagargo/elektroid)
//
// SysEx frame layout:
//   F0               — SysEx start
//   00 20 3C         — Elektron manufacturer ID (3-byte)
//   [device_id]      — 0x0E = Digitakt
//   [msg_type]       — One of ElektronMsgType
//   [payload…]       — Nibble-encoded (each byte → 2 nibbles 0x00–0x0F)
//   [checksum]       — 0x7F & sum of all non-header payload nibbles
//   F7               — SysEx end

// MARK: - Constants

enum ElektronSysEx {
    /// Elektron Music Machines manufacturer ID (3-byte form).
    static let manufacturerID: [UInt8] = [0x00, 0x20, 0x3C]

    /// SysEx device byte for Digitakt (all firmware versions).
    static let digitaktDeviceID: UInt8 = 0x0E

    // MARK: Nibble encoding

    /// Encodes arbitrary bytes for safe transmission inside SysEx (all values ≤ 0x7F).
    /// Each input byte is split into high nibble (bits 7-4) then low nibble (bits 3-0).
    static func nibbleEncode(_ bytes: [UInt8]) -> [UInt8] {
        bytes.flatMap { [($0 >> 4) & 0x0F, $0 & 0x0F] }
    }

    /// Decodes pairs of nibbles back into bytes.
    static func nibbleDecode(_ nibbles: [UInt8]) -> [UInt8] {
        var result = [UInt8]()
        result.reserveCapacity(nibbles.count / 2)
        var i = nibbles.startIndex
        while i + 1 < nibbles.endIndex {
            result.append((nibbles[i] << 4) | nibbles[i + 1])
            i += 2
        }
        return result
    }

    // MARK: Checksum

    static func checksum(over nibbles: [UInt8]) -> UInt8 {
        UInt8(nibbles.map(Int.init).reduce(0, +) & 0x7F)
    }

    // MARK: Message construction

    static func build(
        deviceID: UInt8 = digitaktDeviceID,
        msgType: ElektronMsgType,
        payload: [UInt8] = []
    ) -> [UInt8] {
        let encoded = nibbleEncode(payload)
        let csum = checksum(over: encoded)
        return [0xF0] + manufacturerID + [deviceID, msgType.rawValue]
                      + encoded + [csum, 0xF7]
    }

    // MARK: Parsing

    struct ParsedMessage {
        let deviceID: UInt8
        let msgType: ElektronMsgType
        let payload: [UInt8]     // already nibble-decoded
    }

    static func parse(_ data: Data) -> ParsedMessage? {
        let bytes = [UInt8](data)
        // Minimum: F0 + 3-byte mfr + device + type + checksum + F7 = 8 bytes
        guard bytes.count >= 8,
              bytes.first == 0xF0,
              bytes.last == 0xF7,
              bytes[1] == 0x00, bytes[2] == 0x20, bytes[3] == 0x3C else { return nil }

        let deviceID = bytes[4]
        guard let msgType = ElektronMsgType(rawValue: bytes[5]) else { return nil }

        // Payload nibbles are bytes[6 ..< count-2], last nibble before F7 is checksum
        let nibbles = Array(bytes[6 ..< bytes.count - 2])   // excludes checksum
        // checksum byte is bytes[count-2]
        let payload = nibbleDecode(nibbles)

        return ParsedMessage(deviceID: deviceID, msgType: msgType, payload: payload)
    }
}

// MARK: - Message Types
//
// NOTE: These values are derived from Elektroid reverse-engineering.
//       Verify byte values against real hardware before shipping.

enum ElektronMsgType: UInt8 {
    // Device
    case deviceInfoReq  = 0x01
    case deviceInfoRes  = 0x02

    // Storage
    case storageInfoReq = 0x11
    case storageInfoRes = 0x12

    // Directory / file listing
    case listDirReq     = 0x20
    case listDirRes     = 0x21

    // File read
    case readFileReq    = 0x30   // request: remote path string
    case readFileBegin  = 0x31   // response: total size (4 bytes LE)
    case readFileChunk  = 0x32   // chunk data
    case readFileEnd    = 0x33   // final ack

    // File write
    case writeFileReq   = 0x40   // request: remote path + total size
    case writeFileAck   = 0x41   // device ready to receive
    case writeFileChunk = 0x42   // chunk data
    case writeFileEnd   = 0x43   // transfer complete

    // Delete
    case deleteFileReq  = 0x50
    case deleteFileRes  = 0x51

    // Error / NAK
    case error          = 0x7F
}

// MARK: - Errors

enum ElektronError: LocalizedError {
    case deviceNotFound
    case noResponse(timeout: TimeInterval)
    case unexpectedResponse(ElektronMsgType)
    case transferFailed(String)
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .deviceNotFound:            return "DIGITAKT NOT FOUND — CHECK USB MIDI CONNECTION"
        case .noResponse(let t):         return "DEVICE DID NOT RESPOND WITHIN \(Int(t))S"
        case .unexpectedResponse(let m): return "UNEXPECTED MESSAGE TYPE: \(m)"
        case .transferFailed(let r):     return "TRANSFER FAILED: \(r.uppercased())"
        case .invalidPayload:            return "INVALID RESPONSE PAYLOAD"
        }
    }
}

// MARK: - Payload Helpers

extension [UInt8] {
    /// Encodes a Swift String as null-terminated ASCII bytes.
    static func asciiString(_ s: String) -> [UInt8] {
        Array(s.utf8) + [0x00]
    }

    /// Reads a null-terminated ASCII string from an offset.
    func readCString(at offset: Int) -> (String, endOffset: Int)? {
        guard offset < count else { return nil }
        var end = offset
        while end < count && self[end] != 0x00 { end += 1 }
        let str = String(bytes: self[offset..<end], encoding: .ascii) ?? ""
        return (str, end + 1)
    }

    /// Little-endian UInt32 from 4 bytes at offset.
    func readLE32(at offset: Int) -> UInt32? {
        guard offset + 3 < count else { return nil }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }

    mutating func appendLE32(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
