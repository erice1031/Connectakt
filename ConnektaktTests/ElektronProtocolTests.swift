import Testing
import Foundation
@testable import Connectakt

// MARK: - Elektron Protocol Tests

@Suite("ElektronSysEx")
struct ElektronSysExTests {

    // MARK: - Nibble encoding

    @Test("Nibble-encode: each byte splits into high then low nibble")
    func nibbleEncodeBasic() {
        let input: [UInt8] = [0xAB, 0xCD]
        let encoded = ElektronSysEx.nibbleEncode(input)
        #expect(encoded == [0x0A, 0x0B, 0x0C, 0x0D])
    }

    @Test("Nibble-encode: all encoded values are ≤ 0x0F (safe for SysEx)")
    func nibbleEncodeSysExSafe() {
        let input: [UInt8] = (0...255).map { UInt8($0) }
        let encoded = ElektronSysEx.nibbleEncode(input)
        #expect(encoded.allSatisfy { $0 <= 0x0F })
    }

    @Test("Nibble-decode inverts nibble-encode")
    func nibbleDecodeRoundTrip() {
        let original: [UInt8] = [0x00, 0xFF, 0x1A, 0xB3, 0x42, 0x99]
        let encoded = ElektronSysEx.nibbleEncode(original)
        let decoded = ElektronSysEx.nibbleDecode(encoded)
        #expect(decoded == original)
    }

    @Test("Nibble-decode: odd-length nibble array drops trailing nibble")
    func nibbleDecodeOddLength() {
        // 3 nibbles → 1 byte (third nibble ignored)
        let nibbles: [UInt8] = [0x0A, 0x0B, 0x0C]
        let decoded = ElektronSysEx.nibbleDecode(nibbles)
        #expect(decoded == [0xAB])
    }

    @Test("Nibble-encode empty array returns empty")
    func nibbleEncodeEmpty() {
        #expect(ElektronSysEx.nibbleEncode([]).isEmpty)
    }

    // MARK: - Checksum

    @Test("Checksum is 7-bit (always ≤ 0x7F)")
    func checksumIs7Bit() {
        let nibbles: [UInt8] = Array(repeating: 0x0F, count: 100)
        let csum = ElektronSysEx.checksum(over: nibbles)
        #expect(csum <= 0x7F)
    }

    @Test("Checksum of empty nibbles is 0")
    func checksumEmpty() {
        #expect(ElektronSysEx.checksum(over: []) == 0)
    }

    // MARK: - Message building

    @Test("Built message starts with F0 and ends with F7")
    func builtMessageDelimiters() {
        let msg = ElektronSysEx.build(msgType: .deviceInfoReq)
        #expect(msg.first == 0xF0)
        #expect(msg.last == 0xF7)
    }

    @Test("Built message contains Elektron manufacturer ID")
    func builtMessageContainsManufacturerID() {
        let msg = ElektronSysEx.build(msgType: .deviceInfoReq)
        #expect(msg[1] == 0x00)
        #expect(msg[2] == 0x20)
        #expect(msg[3] == 0x3C)
    }

    @Test("Built message contains default device ID at byte 4")
    func builtMessageDeviceID() {
        let msg = ElektronSysEx.build(msgType: .deviceInfoReq)
        #expect(msg[4] == ElektronSysEx.digitaktDeviceID)
    }

    @Test("Built message encodes msgType byte at position 5")
    func builtMessageMsgType() {
        let msg = ElektronSysEx.build(msgType: .storageInfoReq)
        #expect(msg[5] == ElektronMsgType.storageInfoReq.rawValue)
    }

    @Test("Built message with payload nibble-encodes payload bytes")
    func builtMessagePayloadEncoded() {
        let payload: [UInt8] = [0xAB]
        let msg = ElektronSysEx.build(msgType: .deviceInfoReq, payload: payload)
        // Nibble-encoded payload starts at byte 6
        #expect(msg[6] == 0x0A)   // high nibble of 0xAB
        #expect(msg[7] == 0x0B)   // low  nibble of 0xAB
    }

    // MARK: - Message parsing

    @Test("Parse round-trips through build")
    func parseRoundTrip() {
        let payload: [UInt8] = [0x01, 0x02, 0x03, 0x04]
        let built = ElektronSysEx.build(msgType: .listDirReq, payload: payload)
        let parsed = ElektronSysEx.parse(Data(built))
        #expect(parsed != nil)
        #expect(parsed?.msgType == .listDirReq)
        #expect(parsed?.deviceID == ElektronSysEx.digitaktDeviceID)
        #expect(parsed?.payload == payload)
    }

    @Test("Parse returns nil for non-SysEx data")
    func parseNonSysEx() {
        let data = Data([0x90, 0x3C, 0x64])  // note-on
        #expect(ElektronSysEx.parse(data) == nil)
    }

    @Test("Parse returns nil for data too short to be valid")
    func parseTooShort() {
        let data = Data([0xF0, 0x00, 0x20, 0x3C, 0xF7])
        #expect(ElektronSysEx.parse(data) == nil)
    }

    @Test("Parse returns nil for wrong manufacturer ID")
    func parseWrongManufacturer() {
        let data = Data([0xF0, 0x41, 0x00, 0x00, 0x0E, 0x01, 0x00, 0xF7])
        #expect(ElektronSysEx.parse(data) == nil)
    }

    @Test("Parse returns nil for unknown msgType")
    func parseUnknownMsgType() {
        let data = Data([0xF0, 0x00, 0x20, 0x3C, 0x0E, 0xEE, 0x00, 0xF7])
        #expect(ElektronSysEx.parse(data) == nil)
    }
}

// MARK: - Payload Helper Tests

@Suite("ElektronPayloadHelpers")
struct ElektronPayloadHelperTests {

    @Test("asciiString creates null-terminated byte array")
    func asciiString() {
        let bytes = [UInt8].asciiString("SAMPLES/")
        #expect(bytes.last == 0x00)
        let str = String(bytes: bytes.dropLast(), encoding: .ascii)
        #expect(str == "SAMPLES/")
    }

    @Test("readCString parses a null-terminated string from offset")
    func readCString() {
        let bytes: [UInt8] = Array("KICK.WAV".utf8) + [0x00, 0x00]
        let result = bytes.readCString(at: 0)
        #expect(result?.0 == "KICK.WAV")
        #expect(result?.endOffset == 9)
    }

    @Test("readLE32 decodes 4-byte little-endian value")
    func readLE32() {
        let bytes: [UInt8] = [0x00, 0x10, 0x27, 0x00]  // 0x00_27_10_00 LE = 10,000,000
        let value = bytes.readLE32(at: 0)
        #expect(value == 0x0027_1000)
    }

    @Test("appendLE32 + readLE32 round-trip")
    func le32RoundTrip() {
        var bytes = [UInt8]()
        let original: UInt32 = 123_456_789
        bytes.appendLE32(original)
        #expect(bytes.count == 4)
        #expect(bytes.readLE32(at: 0) == original)
    }
}
