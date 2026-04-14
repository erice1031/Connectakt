import CoreMIDI
import Foundation

// 7-bit codec (mirrors Elektroid)
func encode7(_ bytes: [UInt8]) -> [UInt8] {
    var out = [UInt8]()
    var j = 0
    while j < bytes.count {
        var acc: UInt8 = 0
        for k in 0..<7 {
            acc <<= 1
            if j+k < bytes.count && bytes[j+k] & 0x80 != 0 { acc |= 1 }
        }
        out.append(acc)
        for k in 0..<7 where j+k < bytes.count { out.append(bytes[j+k] & 0x7F) }
        j += 7
    }
    return out
}

func decode7(_ bytes: [UInt8]) -> [UInt8] {
    var out = [UInt8]()
    var i = 0
    while i < bytes.count {
        let acc = bytes[i]
        let n = min(7, bytes.count - i - 1)
        for k in 0..<n {
            out.append((bytes[i+k+1] & 0x7F) | (((acc >> (6-k)) & 1) != 0 ? 0x80 : 0))
        }
        i += 8
    }
    return out
}

let HDR: [UInt8] = [0xF0, 0x00, 0x20, 0x3C, 0x10, 0x00]
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

// MIDI globals
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

func waitFor(_ cmd: UInt8, secs: TimeInterval = 5) -> ElMsg? {
    let deadline = Date().addingTimeInterval(secs)
    while Date() < deadline {
        var found: ElMsg? = nil
        gRxQ.sync {
            if let i = gMsgs.firstIndex(where: { $0.cmd == cmd }) {
                found = gMsgs.remove(at: i)
            }
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
    let raw = UnsafeMutableRawPointer.allocate(byteCount: bufSz,
                                               alignment: MemoryLayout<MIDIPacketList>.alignment)
    defer { raw.deallocate() }
    let lp = raw.assumingMemoryBound(to: MIDIPacketList.self)
    var pkt = MIDIPacketListInit(lp)
    pkt = frame.withUnsafeBytes { MIDIPacketListAdd(lp, bufSz, pkt, 0, frame.count, $0.baseAddress!) }
    MIDISend(gOut, gDst, lp)
}

// ─── Find device ─────────────────────────────────────────────────────────────

print("=== ELEKTRON DIGITAKT SYSEX TEST ===")
let nSrc = MIDIGetNumberOfSources()
let nDst = MIDIGetNumberOfDestinations()
print("Sources: \(nSrc)")
for i in 0..<nSrc { print("  [\(i)] \(midiName(MIDIGetSource(i)))") }
print("Destinations: \(nDst)")
for i in 0..<nDst { print("  [\(i)] \(midiName(MIDIGetDestination(i)))") }

for i in 0..<nSrc {
    let e = MIDIGetSource(i)
    let n = midiName(e).uppercased()
    if n.contains("ELEKTRON") || n.contains("DIGITAKT") { gSrc = e }
}
for i in 0..<nDst {
    let e = MIDIGetDestination(i)
    let n = midiName(e).uppercased()
    if n.contains("ELEKTRON") || n.contains("DIGITAKT") { gDst = e }
}
guard gSrc != 0, gDst != 0 else { print("DEVICE NOT FOUND"); exit(1) }
print("Device: \(midiName(gSrc))\n")

// ─── Open ports ───────────────────────────────────────────────────────────────

MIDIClientCreate("EmTest" as CFString, nil, nil, &gClient)
MIDIOutputPortCreate(gClient, "EmOut" as CFString, &gOut)
MIDIInputPortCreate(gClient, "EmIn" as CFString, { pktList, _, _ in
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

// ─── STEP 1: Ping ─────────────────────────────────────────────────────────────

print("STEP 1 — PING (0x01 -> 0x81)")
sendMsg(0x01)
if let r = waitFor(0x81, secs: 5) {
    print("  PASS  status=\(r.status) payload[\(r.payload.count)]")
    let printable = r.payload.filter { $0 >= 0x20 && $0 < 0x7F }
    if !printable.isEmpty, let info = String(bytes: printable, encoding: .ascii) {
        print("  info: \"\(info)\"")
    }
} else {
    print("  TIMEOUT — check SETTINGS > SYSTEM > USB CONFIG")
}

// ─── STEP 2: listDir "/" ─────────────────────────────────────────────────────

print("\nSTEP 2 — LIST DIR \"/\" (0x10 -> 0x90)")
sendMsg(0x10, payload: [0x2F, 0x00])
if let r = waitFor(0x90, secs: 8) {
    print("  PASS  \(r.payload.count) bytes")
    let hexFull = r.payload.map { String(format: "%02X", $0) }.joined(separator: " ")
    print("  HEX:  \(hexFull)")

    // Parse: hash(4) + size(4) + write_prot(1) + item_type(1) + name(NUL)
    var entries = [(name: String, size: UInt32, isDir: Bool, typeRaw: UInt8)]()
    var pos = 0
    let p = r.payload
    while pos < p.count {
        guard pos + 10 <= p.count else { break }
        pos += 4
        let sz = be32(p, at: pos); pos += 4
        pos += 1
        let t = p[pos]; pos += 1
        var end = pos
        while end < p.count && p[end] != 0 { end += 1 }
        let name = String(bytes: p[pos..<end], encoding: .ascii) ?? "???"
        pos = end + 1
        if !name.isEmpty { entries.append((name, sz, t == 0x44, t)) }
    }

    print(String(format: "\n  %-36@ %10@  TYPE", "NAME", "SIZE"))
    print("  " + String(repeating: "-", count: 52))
    for e in entries {
        print(String(format: "  %-36@ %10@  0x%02X %@",
              e.name, e.isDir ? "<DIR>" : "\(e.size)B",
              e.typeRaw, e.isDir ? "(dir)" : ""))
    }
    print("  Total: \(entries.count) entries")
} else {
    print("  TIMEOUT")
}

// ─── STEP 3: Storage info ─────────────────────────────────────────────────────

print("\nSTEP 3 — STORAGE INFO (0x05 -> 0x85)")
sendMsg(0x05)
if let r = waitFor(0x85, secs: 5) {
    print("  PASS  status=\(r.status) payload[\(r.payload.count)]")
    print("  HEX:  \(r.payload.map { String(format: "%02X", $0) }.joined(separator: " "))")
    if r.payload.count >= 8 {
        let used  = be32(r.payload, at: 0)
        let total = be32(r.payload, at: 4)
        let pct = total > 0 ? 100 * Double(used) / Double(total) : 0
        print(String(format: "  Used %.1f MB / %.1f MB  (%.0f%% full)",
              Double(used)/1_048_576, Double(total)/1_048_576, pct))
    }
} else {
    print("  TIMEOUT (cmd 0x05 may not be supported on this firmware)")
}

print("\n=== DONE ===")
MIDIClientDispose(gClient)
