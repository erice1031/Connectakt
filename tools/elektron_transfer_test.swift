import CoreMIDI
import Foundation

// ─── 7-bit codec ─────────────────────────────────────────────────────────────

func encode7(_ bytes: [UInt8]) -> [UInt8] {
    var out = [UInt8](); var j = 0
    while j < bytes.count {
        var acc: UInt8 = 0
        for k in 0..<7 { acc <<= 1; if j+k < bytes.count && bytes[j+k] & 0x80 != 0 { acc |= 1 } }
        out.append(acc)
        for k in 0..<7 where j+k < bytes.count { out.append(bytes[j+k] & 0x7F) }
        j += 7
    }
    return out
}

func decode7(_ bytes: [UInt8]) -> [UInt8] {
    var out = [UInt8](); var i = 0
    while i < bytes.count {
        let acc = bytes[i]; let n = min(7, bytes.count - i - 1)
        for k in 0..<n { out.append((bytes[i+k+1] & 0x7F) | (((acc >> (6-k)) & 1) != 0 ? 0x80 : 0)) }
        i += 8
    }
    return out
}

// ─── Protocol ─────────────────────────────────────────────────────────────────

let HDR: [UInt8] = [0xF0, 0x00, 0x20, 0x3C, 0x10, 0x00]
// Commands that carry raw data at decoded[5] — no status byte.
let DATA_CMDS: Set<UInt8> = [0x90, 0xB2]

struct ElMsg { let cmd: UInt8; let status: UInt8; let payload: [UInt8] }

func buildSysEx(_ seq: UInt16, _ cmd: UInt8, _ payload: [UInt8] = []) -> [UInt8] {
    let body: [UInt8] = [UInt8(seq>>8), UInt8(seq & 0xFF), 0, 0, cmd] + payload
    return HDR + encode7(body) + [0xF7]
}

func parseSysEx(_ raw: [UInt8]) -> ElMsg? {
    guard raw.count > HDR.count + 1, raw.last == 0xF7, raw.starts(with: HDR) else { return nil }
    let dec = decode7(Array(raw[HDR.count ..< raw.count-1]))
    guard dec.count >= 5 else { return nil }
    let cmd = dec[4]
    if DATA_CMDS.contains(cmd) {
        return ElMsg(cmd: cmd, status: 0, payload: dec.count > 5 ? Array(dec[5...]) : [])
    }
    guard dec.count >= 6 else { return nil }
    return ElMsg(cmd: cmd, status: dec[5], payload: dec.count > 6 ? Array(dec[6...]) : [])
}

func be32(_ b: [UInt8], at i: Int) -> UInt32 {
    guard i + 3 < b.count else { return 0 }
    return (UInt32(b[i]) << 24) | (UInt32(b[i+1]) << 16) | (UInt32(b[i+2]) << 8) | UInt32(b[i+3])
}

func appendBE32(_ val: UInt32) -> [UInt8] {
    [UInt8((val>>24) & 0xFF), UInt8((val>>16) & 0xFF), UInt8((val>>8) & 0xFF), UInt8(val & 0xFF)]
}

func asciiZ(_ s: String) -> [UInt8] { Array(s.utf8) + [0x00] }

// ─── MIDI globals ─────────────────────────────────────────────────────────────

var gClient: MIDIClientRef   = 0
var gOut:    MIDIPortRef     = 0
var gIn:     MIDIPortRef     = 0
var gSrc:    MIDIEndpointRef = 0
var gDst:    MIDIEndpointRef = 0
var gSeq:    UInt16 = 0
var gBuf     = Data()
var gMsgs    = [ElMsg]()
let gRxQ     = DispatchQueue(label: "rx")

func midiName(_ e: MIDIEndpointRef) -> String {
    var cf: Unmanaged<CFString>?
    MIDIObjectGetStringProperty(e, kMIDIPropertyName, &cf)
    return (cf?.takeRetainedValue() as String?) ?? "<unknown>"
}

func waitFor(_ cmd: UInt8, secs: TimeInterval = 10) -> ElMsg? {
    let deadline = Date().addingTimeInterval(secs)
    while Date() < deadline {
        var found: ElMsg? = nil
        gRxQ.sync {
            if let i = gMsgs.firstIndex(where: { $0.cmd == cmd }) { found = gMsgs.remove(at: i) }
        }
        if let m = found { return m }
        Thread.sleep(forTimeInterval: 0.05)
    }
    return nil
}

func sendMsg(_ cmd: UInt8, payload: [UInt8] = []) {
    let seq = gSeq; gSeq &+= 1
    let frame = buildSysEx(seq, cmd, payload)
    let bufSz = MemoryLayout<MIDIPacketList>.size + frame.count
    let raw = UnsafeMutableRawPointer.allocate(byteCount: bufSz, alignment: MemoryLayout<MIDIPacketList>.alignment)
    defer { raw.deallocate() }
    let lp = raw.assumingMemoryBound(to: MIDIPacketList.self)
    var pkt = MIDIPacketListInit(lp)
    pkt = frame.withUnsafeBytes { MIDIPacketListAdd(lp, bufSz, pkt, 0, frame.count, $0.baseAddress!) }
    MIDISend(gOut, gDst, lp)
}

// Expects status=1. Returns payload or nil.
func sendAndExpect(_ cmd: UInt8, respCmd: UInt8, payload: [UInt8] = [], timeout: TimeInterval = 10) -> [UInt8]? {
    sendMsg(cmd, payload: payload)
    guard let r = waitFor(respCmd, secs: timeout) else { print("  TIMEOUT waiting for 0x\(String(format:"%02X",respCmd))"); return nil }
    if !DATA_CMDS.contains(respCmd) && r.status != 1 {
        print("  ERROR: status=\(r.status) from 0x\(String(format:"%02X",respCmd))")
        return nil
    }
    return r.payload
}

// ─── Find & open device ───────────────────────────────────────────────────────

print("=== ELEKTRON TRANSFER TEST ===\n")
let nSrc = MIDIGetNumberOfSources(); let nDst = MIDIGetNumberOfDestinations()
for i in 0..<nSrc {
    let e = MIDIGetSource(i); let n = midiName(e).uppercased()
    if n.contains("ELEKTRON") || n.contains("DIGITAKT") { gSrc = e }
}
for i in 0..<nDst {
    let e = MIDIGetDestination(i); let n = midiName(e).uppercased()
    if n.contains("ELEKTRON") || n.contains("DIGITAKT") { gDst = e }
}
guard gSrc != 0, gDst != 0 else { print("DEVICE NOT FOUND"); exit(1) }
print("Device: \(midiName(gSrc))\n")

MIDIClientCreate("XferTest" as CFString, nil, nil, &gClient)
MIDIOutputPortCreate(gClient, "XferOut" as CFString, &gOut)
MIDIInputPortCreate(gClient, "XferIn" as CFString, { pktList, _, _ in
    var pkts = [[UInt8]]()
    withUnsafePointer(to: pktList.pointee.packet) { first in
        var p: UnsafePointer<MIDIPacket> = first
        for _ in 0..<Int(pktList.pointee.numPackets) {
            let len = Int(p.pointee.length)
            if len > 0 {
                pkts.append(withUnsafePointer(to: p.pointee.data) {
                    [UInt8](UnsafeRawBufferPointer(start: $0, count: len))
                })
            }
            p = UnsafePointer(MIDIPacketNext(UnsafeMutablePointer(mutating: p)))
        }
    }
    gRxQ.async {
        for bytes in pkts {
            gBuf.append(contentsOf: bytes)
            while let f0 = gBuf.firstIndex(of: 0xF0) {
                if f0 > gBuf.startIndex { gBuf.removeSubrange(gBuf.startIndex..<f0) }
                guard let f7 = gBuf.firstIndex(of: 0xF7) else { break }
                let raw = [UInt8](gBuf[gBuf.startIndex...f7])
                gBuf.removeSubrange(gBuf.startIndex...f7)
                if let msg = parseSysEx(raw) { gMsgs.append(msg) }
            }
        }
    }
}, nil, &gIn)
MIDIPortConnectSource(gIn, gSrc, nil)
Thread.sleep(forTimeInterval: 0.3)

// ─── Ping ─────────────────────────────────────────────────────────────────────

print("STEP 1 — PING")
sendMsg(0x01)
guard let pr = waitFor(0x81, secs: 5) else { print("  TIMEOUT — check SETTINGS > SYSTEM > USB CONFIG"); exit(1) }
print("  PASS  (device type=\(pr.status))\n")

// ─── Build test file: minimal Elektron internal format ────────────────────────
// 64-byte header + 200 samples × 2 bytes BE PCM (a gentle fade-in ramp)
// Header layout (from app code): bytes 10-11=sampleRate BE, 16-19=sampleCount BE, 20=0x7F, rest=0

let sampleCount: UInt32 = 200
var testFile = [UInt8](repeating: 0, count: 64)
testFile[10] = 0xAC; testFile[11] = 0x44          // 44100 Hz
testFile[16] = UInt8((sampleCount >> 24) & 0xFF)
testFile[17] = UInt8((sampleCount >> 16) & 0xFF)
testFile[18] = UInt8((sampleCount >>  8) & 0xFF)
testFile[19] = UInt8( sampleCount        & 0xFF)
testFile[20] = 0x7F
// Append PCM: ramp 0..199 mapped to 0..0x3E00 (well below clipping), stored BE
for s in 0..<Int(sampleCount) {
    let sample = UInt16(s * 100)   // gentle ramp, max 19900, well within UInt16
    testFile.append(UInt8(sample >> 8))
    testFile.append(UInt8(sample & 0xFF))
}
print("Test file: \(testFile.count) bytes  (64-byte header + \(sampleCount) samples)\n")

// ─── UPLOAD ───────────────────────────────────────────────────────────────────

let remotePath = "/test/CLTEST.wav"
let chunkSize  = 512

print("STEP 2 — UPLOAD  \(remotePath)  (\(testFile.count) bytes)")

// 2a — Open writer: fileSize(4 BE) + path(nullZ)
let openWrPayload = appendBE32(UInt32(testFile.count)) + asciiZ(remotePath)
guard let openWrResp = sendAndExpect(0x40, respCmd: 0xC0, payload: openWrPayload, timeout: 10) else {
    print("  UPLOAD FAILED: open writer"); exit(1)
}
let writeHandle = be32(openWrResp, at: 0)
print("  open writer OK  handle=0x\(String(format:"%08X", writeHandle))")

// 2b — Write chunks
var offset = 0; var chunkN = 0
while offset < testFile.count {
    let end       = min(offset + chunkSize, testFile.count)
    let chunk     = Array(testFile[offset..<end])
    var wp: [UInt8] = []
    wp += appendBE32(writeHandle)
    wp += appendBE32(UInt32(chunk.count))
    wp += appendBE32(UInt32(offset))
    wp += chunk
    guard sendAndExpect(0x42, respCmd: 0xC2, payload: wp) != nil else {
        print("  UPLOAD FAILED: write chunk \(chunkN)"); exit(1)
    }
    chunkN += 1; offset = end
    print("  chunk \(chunkN): \(chunk.count) bytes @ offset \(offset - chunk.count)  OK")
}

// 2c — Close writer: handle(4 BE) + totalBytes(4 BE)
let closeWrPayload = appendBE32(writeHandle) + appendBE32(UInt32(testFile.count))
guard sendAndExpect(0x41, respCmd: 0xC1, payload: closeWrPayload) != nil else {
    print("  UPLOAD FAILED: close writer"); exit(1)
}
print("  close writer OK")
print("  UPLOAD COMPLETE\n")

// ─── DOWNLOAD ────────────────────────────────────────────────────────────────

print("STEP 3 — DOWNLOAD  \(remotePath)")

// 3a — Open reader: path(nullZ)
guard let openRdResp = sendAndExpect(0x30, respCmd: 0xB0, payload: asciiZ(remotePath), timeout: 10) else {
    print("  DOWNLOAD FAILED: open reader"); exit(1)
}
let readHandle = be32(openRdResp, at: 0)
let fileSize   = be32(openRdResp, at: 4)
print("  open reader OK  handle=0x\(String(format:"%08X",readHandle))  size=\(fileSize) bytes")
guard fileSize > 0 else { print("  DOWNLOAD FAILED: reported size is 0"); exit(1) }

// 3b — Read chunks
// readChunkReq payload: handle(4) + chunkSize(4) + byteOffset(4)
// readChunkRes (DATA_CMD): [0]=status [1-4]=handleEcho [5-8]=chunkSzEcho [9-12]=offsetEcho
//                          [13-16]=cumulativeBytes [17+]=data
var received = [UInt8]()
var remaining = Int(fileSize)
var blockIdx: UInt32 = 0
while remaining > 0 {
    let reqChunk = min(chunkSize, remaining)
    var rp: [UInt8] = []
    rp += appendBE32(readHandle)
    rp += appendBE32(UInt32(reqChunk))
    rp += appendBE32(blockIdx * UInt32(chunkSize))
    sendMsg(0x32, payload: rp)
    guard let r = waitFor(0xB2, secs: 10) else { print("  TIMEOUT on readChunk \(blockIdx)"); break }
    // payload[0] = status: 0x00=EOF, non-zero=data follows
    if r.payload.first == 0x00 { print("  EOF at block \(blockIdx)"); break }
    let dataStart = 17
    guard r.payload.count > dataStart else { print("  short readChunk payload (\(r.payload.count) bytes)"); break }
    let chunk = Array(r.payload[dataStart...])
    received += chunk
    remaining -= chunk.count
    blockIdx  += 1
    print("  chunk \(blockIdx): got \(chunk.count) bytes  total \(received.count)/\(fileSize)")
}

// 3c — Close reader (no payload needed per app code)
sendMsg(0x31, payload: [])
_ = waitFor(0xB1, secs: 5)   // ignore result
print("  close reader done")

// ─── Verify round-trip ───────────────────────────────────────────────────────

print("\nSTEP 4 — VERIFY")
if received.count == testFile.count && received == testFile {
    print("  PASS: \(received.count) bytes match exactly")
} else if received.isEmpty {
    print("  FAIL: received nothing")
} else {
    print("  FAIL: sent \(testFile.count) bytes, got \(received.count) bytes")
    // Find first mismatch
    let cmp = min(received.count, testFile.count)
    for i in 0..<cmp {
        if received[i] != testFile[i] {
            print("  First mismatch at byte \(i): sent 0x\(String(format:"%02X",testFile[i])) got 0x\(String(format:"%02X",received[i]))")
            break
        }
    }
}

// ─── Delete test file ─────────────────────────────────────────────────────────

print("\nSTEP 5 — DELETE  \(remotePath)")
guard sendAndExpect(0x20, respCmd: 0xA0, payload: asciiZ(remotePath)) != nil else {
    print("  DELETE FAILED (file may remain on device)")
    MIDIClientDispose(gClient); exit(0)
}
print("  PASS: file deleted\n")

print("=== DONE ===")
MIDIClientDispose(gClient)
