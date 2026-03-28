import Foundation

// MARK: - Elektron SysEx Protocol (v2 — Digitakt / new-gen devices)
//
// Reference: Elektroid open-source project (https://github.com/dagargo/elektroid)
//            src/connectors/elektron.c
//
// SysEx frame layout:
//   F0 00 20 3C 10 00     — header (Elektron mfr ID + device family)
//   [7-bit encoded body]  — see encode7bit / decode7bit
//   F7                    — SysEx end
//
// Decoded message body layout (before 7-bit encoding):
//   [0-1]  UInt16 BE   — sequence number (increments per request)
//   [2-3]  0x00 0x00   — reserved
//   [4]    UInt8       — command type (ElektronMsgType rawValue)
//   [5]    UInt8       — status byte in responses (0=error 1=success); first payload byte in requests
//   [6+]               — payload
//
// 7-bit encoding packs 7 input bytes into 8 output bytes:
//   output[0]        = accumulated MSBs of input[0..6] (bit6 = MSB of input[0], …, bit0 = MSB of input[6])
//   output[1..7]     = input[0..6] & 0x7F
// Ensures all SysEx payload bytes are < 0x80.

// MARK: - Constants

enum ElektronSysEx {
    /// Fixed SysEx header: F0 + Elektron 3-byte mfr ID + device family byte + reserved.
    static let header: [UInt8] = [0xF0, 0x00, 0x20, 0x3C, 0x10, 0x00]

    // MARK: - 7-bit Encoding

    /// Encodes `bytes` for safe transmission inside SysEx (all values < 0x80).
    /// Mirrors `elektron_encode_payload` from elektroid/src/connectors/elektron.c.
    static func encode7bit(_ bytes: [UInt8]) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(bytes.count + Int(ceil(Double(bytes.count) / 7.0)))
        var j = 0
        while j < bytes.count {
            // Accumulate MSBs of up to 7 bytes (always shift 7 times to match C reference)
            var accum: UInt8 = 0
            for k in 0..<7 {
                accum <<= 1
                if j + k < bytes.count, bytes[j + k] & 0x80 != 0 { accum |= 1 }
            }
            result.append(accum)
            for k in 0..<7 where j + k < bytes.count {
                result.append(bytes[j + k] & 0x7F)
            }
            j += 7
        }
        return result
    }

    /// Decodes a 7-bit-encoded payload back to raw bytes.
    /// Mirrors `elektron_decode_payload` from elektroid/src/connectors/elektron.c.
    static func decode7bit(_ bytes: [UInt8]) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(bytes.count - Int(ceil(Double(bytes.count) / 8.0)))
        var i = 0
        while i < bytes.count {
            let accum = bytes[i]
            let count = min(7, bytes.count - i - 1)
            for k in 0..<count {
                let lower = bytes[i + k + 1] & 0x7F
                let msb: UInt8 = ((accum >> (6 - k)) & 1) != 0 ? 0x80 : 0
                result.append(lower | msb)
            }
            i += 8
        }
        return result
    }

    // MARK: - Message Construction

    /// Builds a complete SysEx frame ready to send.
    /// `seq` should be a monotonically incrementing counter per transfer session.
    static func build(
        seq: UInt16,
        msgType: ElektronMsgType,
        payload: [UInt8] = []
    ) -> [UInt8] {
        // Decoded body: seq(2) + reserved(2) + cmd(1) + payload
        var body: [UInt8] = [
            UInt8(seq >> 8), UInt8(seq & 0xFF),
            0x00, 0x00,
            msgType.rawValue
        ]
        body.append(contentsOf: payload)
        return header + encode7bit(body) + [0xF7]
    }

    // MARK: - Parsing

    struct ParsedMessage {
        let seq: UInt16
        let msgType: ElektronMsgType
        let status: UInt8      // 1 = success, 0 = error (responses only)
        let payload: [UInt8]   // everything after the status byte
    }

    static func parse(_ data: Data) -> ParsedMessage? {
        let bytes = [UInt8](data)
        guard bytes.count > header.count + 1,
              bytes.last == 0xF7,
              bytes.starts(with: header) else { return nil }

        let encoded = Array(bytes[header.count ..< bytes.count - 1])
        let decoded = decode7bit(encoded)

        guard decoded.count >= 6 else { return nil }

        let seq     = (UInt16(decoded[0]) << 8) | UInt16(decoded[1])
        let rawCmd  = decoded[4]
        let status  = decoded[5]

        guard let msgType = ElektronMsgType(rawValue: rawCmd) else { return nil }
        let payload = decoded.count > 6 ? Array(decoded[6...]) : []

        return ParsedMessage(seq: seq, msgType: msgType, status: status, payload: payload)
    }
}

// MARK: - Message Types
//
// Requests:  cmd byte < 0x80
// Responses: cmd byte = request | 0x80
// Source: elektroid/src/connectors/elektron.c

enum ElektronMsgType: UInt8 {
    // ---- Requests ----
    case ping            = 0x01
    case deviceUID       = 0x03
    case storageInfoReq  = 0x05

    /// List directory. Payload: null-terminated path string.
    case listDirReq      = 0x10

    /// Delete file. Payload: null-terminated path string.
    case deleteFileReq   = 0x20

    /// Open a file for reading. Payload: null-terminated path string.
    case openReaderReq   = 0x30
    /// Close the open reader.
    case closeReaderReq  = 0x31
    /// Read a chunk. Payload: offset(4 BE) + chunkSize(4 BE) + reserved(4).
    case readChunkReq    = 0x32

    /// Open a file for writing. Payload: fileSize(4 BE) + null-terminated path string.
    case openWriterReq   = 0x40
    /// Write a chunk. Payload: offset(4 BE) + chunkSize(4 BE) + reserved(4) + data bytes.
    case writeChunkReq   = 0x42

    // ---- Responses (request | 0x80) ----
    case pingRes         = 0x81
    case storageInfoRes  = 0x85

    /// List directory response. Payload: repeated entries — see parseFileListing.
    case listDirRes      = 0x90

    case deleteFileRes   = 0xA0

    /// Open reader response. Payload: fileSize(4 BE).
    case openReaderRes   = 0xB0
    case closeReaderRes  = 0xB1
    /// Read chunk response. Payload: chunk data bytes.
    case readChunkRes    = 0xB2

    /// Open writer response (device ready to receive).
    case openWriterRes   = 0xC0
    /// Write chunk ack.
    case writeChunkRes   = 0xC2

    case error           = 0xFF
}

// MARK: - Directory Entry Parsing
//
// Each entry in a listDirRes payload:
//   hash         — 4 bytes, big-endian UInt32
//   size         — 4 bytes, big-endian UInt32
//   write_prot   — 1 byte flag
//   item_type    — 1 byte (non-zero = directory / folder)
//   name         — null-terminated ASCII string (CP1252, ASCII for sample names)

extension ElektronSysEx {
    /// Parses the payload of a `listDirRes` message into SampleFile entries.
    static func parseFileListing(_ payload: [UInt8]) -> [SampleFile] {
        var files: [SampleFile] = []
        var pos = 0
        while pos < payload.count {
            // hash (4 bytes BE) — not used by the app, skip
            guard pos + 4 <= payload.count else { break }
            pos += 4

            // size (4 bytes BE)
            guard pos + 4 <= payload.count,
                  let size = payload.readBE32(at: pos) else { break }
            pos += 4

            // write_protected flag (1 byte) — skip
            guard pos < payload.count else { break }
            pos += 1

            // item_type (1 byte): 0 = file, non-zero = directory
            guard pos < payload.count else { break }
            let isFolder = payload[pos] != 0
            pos += 1

            // null-terminated name
            guard let (name, afterName) = payload.readCString(at: pos),
                  !name.isEmpty else { break }
            pos = afterName

            files.append(SampleFile(name: name, size: Int64(size), isFolder: isFolder))
        }
        return files
    }
}

// MARK: - Errors

enum ElektronError: LocalizedError {
    case deviceNotFound
    case noResponse(timeout: TimeInterval)
    case unexpectedResponse(ElektronMsgType)
    case deviceError(status: UInt8)
    case transferFailed(String)
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .deviceNotFound:            return "DIGITAKT NOT FOUND — CHECK USB MIDI CONNECTION"
        case .noResponse(let t):         return "DEVICE DID NOT RESPOND WITHIN \(Int(t))S"
        case .unexpectedResponse(let m): return "UNEXPECTED MESSAGE TYPE: \(m)"
        case .deviceError(let s):        return "DEVICE RETURNED ERROR (STATUS \(s))"
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

    /// Reads a null-terminated ASCII string starting at `offset`.
    func readCString(at offset: Int) -> (String, endOffset: Int)? {
        guard offset < count else { return nil }
        var end = offset
        while end < count && self[end] != 0x00 { end += 1 }
        let str = String(bytes: self[offset..<end], encoding: .ascii) ?? ""
        return (str, end + 1)
    }

    /// Big-endian UInt32 from 4 bytes at offset.
    func readBE32(at offset: Int) -> UInt32? {
        guard offset + 3 < count else { return nil }
        return (UInt32(self[offset])     << 24)
             | (UInt32(self[offset + 1]) << 16)
             | (UInt32(self[offset + 2]) <<  8)
             |  UInt32(self[offset + 3])
    }

    /// Appends a UInt32 as big-endian bytes.
    mutating func appendBE32(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >>  8) & 0xFF))
        append(UInt8( value        & 0xFF))
    }

    /// Little-endian UInt32 (kept for any legacy use).
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
