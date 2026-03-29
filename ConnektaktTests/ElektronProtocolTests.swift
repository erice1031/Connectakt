import Testing
import Foundation
@testable import Connectakt

// MARK: - Elektron SysEx Tests

@Suite("ElektronSysEx")
struct ElektronSysExTests {

    @Test("7-bit encode keeps all output bytes below 0x80")
    func encode7BitProducesSysExSafeBytes() {
        let input: [UInt8] = (0...255).map(UInt8.init)
        let encoded = ElektronSysEx.encode7bit(input)
        #expect(encoded.allSatisfy { $0 < 0x80 })
    }

    @Test("7-bit decode round-trips encoded payload")
    func encodeDecodeRoundTrip() {
        let original: [UInt8] = [0x00, 0x7F, 0x80, 0xFF, 0x10, 0x42, 0x99, 0xAB, 0xCD]
        let encoded = ElektronSysEx.encode7bit(original)
        let decoded = ElektronSysEx.decode7bit(encoded)
        #expect(decoded == original)
    }

    @Test("Build wraps messages in Elektron SysEx header and trailer")
    func buildIncludesHeaderAndTrailer() {
        let message = ElektronSysEx.build(seq: 0x1234, msgType: .storageInfoReq)
        #expect(Array(message.prefix(ElektronSysEx.header.count)) == ElektronSysEx.header)
        #expect(message.last == 0xF7)
    }

    @Test("Parse round-trips built messages")
    func parseRoundTrip() {
        let payload: [UInt8] = [0x01, 0x7F, 0x80, 0xFF]
        let built = ElektronSysEx.build(seq: 0x0102, msgType: .listDirReq, payload: payload)
        let parsed = ElektronSysEx.parse(Data(built))

        #expect(parsed != nil)
        #expect(parsed?.seq == 0x0102)
        #expect(parsed?.msgType == .listDirReq)
        #expect(parsed?.status == payload.first)
        #expect(parsed?.payload == Array(payload.dropFirst()))
    }

    @Test("Parse rejects invalid manufacturer header")
    func parseRejectsInvalidHeader() {
        let bytes = Data([0xF0, 0x01, 0x02, 0x03, 0x04, 0xF7])
        #expect(ElektronSysEx.parse(bytes) == nil)
    }

    @Test("Parse rejects unknown command byte")
    func parseRejectsUnknownCommand() {
        let body: [UInt8] = [0x00, 0x01, 0x00, 0x00, 0x7E, 0x00]
        let bytes = ElektronSysEx.header + ElektronSysEx.encode7bit(body) + [0xF7]
        #expect(ElektronSysEx.parse(Data(bytes)) == nil)
    }

    @Test("File listing parser decodes files and folders")
    func parseFileListing() {
        var payload: [UInt8] = []

        payload.append(contentsOf: [0x00, 0x00, 0x00, 0x01]) // hash
        payload.append(contentsOf: [0x00, 0x00, 0x10, 0x00]) // size
        payload.append(0x00) // write protected
        payload.append(0x00) // file
        payload.append(contentsOf: [UInt8].asciiString("KICK.WAV"))

        payload.append(contentsOf: [0x00, 0x00, 0x00, 0x02]) // hash
        payload.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // size
        payload.append(0x00) // write protected
        payload.append(0x01) // folder
        payload.append(contentsOf: [UInt8].asciiString("SAMPLES"))

        let files = ElektronSysEx.parseFileListing(payload)
        #expect(files.count == 2)
        #expect(files[0].name == "KICK.WAV")
        #expect(files[0].size == 4096)
        #expect(files[0].isFolder == false)
        #expect(files[1].name == "SAMPLES")
        #expect(files[1].size == 0)
        #expect(files[1].isFolder == true)
    }
}

// MARK: - Payload Helpers

@Suite("ElektronPayloadHelpers")
struct ElektronPayloadHelperTests {

    @Test("asciiString creates null-terminated bytes")
    func asciiString() {
        let bytes = [UInt8].asciiString("SAMPLES/")
        #expect(bytes.last == 0x00)
        #expect(String(bytes: bytes.dropLast(), encoding: .ascii) == "SAMPLES/")
    }

    @Test("readCString returns string and next offset")
    func readCString() {
        let bytes: [UInt8] = Array("KICK.WAV".utf8) + [0x00, 0x00]
        let result = bytes.readCString(at: 0)
        #expect(result?.0 == "KICK.WAV")
        #expect(result?.endOffset == 9)
    }

    @Test("appendBE32 and readBE32 round-trip")
    func bigEndianRoundTrip() {
        var bytes = [UInt8]()
        let original: UInt32 = 123_456_789
        bytes.appendBE32(original)
        #expect(bytes.count == 4)
        #expect(bytes.readBE32(at: 0) == original)
    }

    @Test("appendLE32 and readLE32 round-trip")
    func littleEndianRoundTrip() {
        var bytes = [UInt8]()
        let original: UInt32 = 987_654_321
        bytes.appendLE32(original)
        #expect(bytes.count == 4)
        #expect(bytes.readLE32(at: 0) == original)
    }
}
