import CoreMIDI
import Foundation

// MARK: - ElektronMIDITransfer
//
// DigitaktTransferProtocol implementation via CoreMIDI + Elektron SysEx v2.
//
// Wire format: 7-bit-encoded SysEx with 6-byte header {F0 00 20 3C 10 00}.
// All file-management commands use the open/read-or-write/close pattern.
//
// Reference: Elektroid (https://github.com/dagargo/elektroid)

final class ElektronMIDITransfer: DigitaktTransferProtocol {

    private let device: ElektronDeviceInfo
    private let mailbox = ElektronMailbox()

    private var midiClient: MIDIClientRef = 0
    private var outputPort: MIDIPortRef = 0
    private var inputPort:  MIDIPortRef = 0

    private var seqCounter: UInt16 = 0

    /// SysEx reassembly buffer — CoreMIDI may split large SysEx across multiple MIDIPackets.
    private var sysExBuffer = Data()

    private let defaultTimeout: TimeInterval = 10
    /// Chunk size for file writes (bytes of raw payload per chunk).
    /// 0x200 (512 B) is conservative for SysEx over MIDI; tune up after hardware validation.
    private let writeChunkSize = 0x200

    // MARK: - Init

    init(device: ElektronDeviceInfo) throws {
        self.device = device
        try openPorts()
    }

    deinit {
        if midiClient != 0 { MIDIClientDispose(midiClient) }
    }

    // MARK: - CoreMIDI Port Setup

    private func openPorts() throws {
        let readBlock: MIDIReadBlock = { [weak self] packetList, _ in
            guard let self else { return }
            let numPackets = Int(packetList.pointee.numPackets)
            withUnsafePointer(to: packetList.pointee.packet) { first in
                var pkt: UnsafePointer<MIDIPacket> = first
                for _ in 0..<numPackets {
                    let length = Int(pkt.pointee.length)
                    if length > 0 {
                        let data = withUnsafePointer(to: pkt.pointee.data) { ptr in
                            Data(UnsafeRawBufferPointer(start: ptr, count: length))
                        }
                        Task { await self.feedBytes(data) }
                    }
                    pkt = UnsafePointer(MIDIPacketNext(UnsafeMutablePointer(mutating: pkt)))
                }
            }
        }

        var status = MIDIClientCreate("ConnektaktTransfer" as CFString, nil, nil, &midiClient)
        guard status == noErr else { throw ElektronError.transferFailed("MIDI client \(status)") }

        status = MIDIOutputPortCreate(midiClient, "ConnektaktOut" as CFString, &outputPort)
        guard status == noErr else { throw ElektronError.transferFailed("output port \(status)") }

        status = MIDIInputPortCreateWithBlock(midiClient, "ConnektaktIn" as CFString, &inputPort, readBlock)
        guard status == noErr else { throw ElektronError.transferFailed("input port \(status)") }

        MIDIPortConnectSource(inputPort, device.source, nil)
    }

    // MARK: - SysEx Reassembly
    //
    // CoreMIDI may deliver a single SysEx across several MIDIPackets.
    // We accumulate bytes and dispatch each complete F0…F7 frame.

    // Both methods are @MainActor to serialize all buffer mutations on a single
    // executor. CoreMIDI delivers packets on a background thread and each packet
    // spawns a Task; without isolation two tasks can race on sysExBuffer — one
    // extracts a frame and suspends at `await handleFrame`, the other appends
    // more data and calls removeSubrange, leaving the first task with stale
    // indices when it resumes → "Range requires lowerBound <= upperBound" crash.

    @MainActor
    private func feedBytes(_ data: Data) async {
        sysExBuffer.append(data)
        while let f0 = sysExBuffer.firstIndex(of: 0xF0),
              let f7 = sysExBuffer[f0...].firstIndex(of: 0xF7) {
            let frame = sysExBuffer[f0...f7]
            sysExBuffer.removeSubrange(sysExBuffer.startIndex...f7)
            await handleFrame(Data(frame))
        }
        if sysExBuffer.count > 1_048_576 { sysExBuffer.removeAll() }
    }

    @MainActor
    private func handleFrame(_ data: Data) async {
        guard let parsed = ElektronSysEx.parse(data) else { return }
        if parsed.msgType == .error {
            await mailbox.abortAll(with: ElektronError.deviceError(status: parsed.status))
            return
        }
        // Data responses carry raw bytes starting at decoded[5] — no status byte.
        // Command responses have a status byte at decoded[5] (0x01=success, 0x00=error).
        //
        // Hardware-confirmed exceptions (probe against a live Digitakt):
        //   • listDirRes, readChunkRes  — data only, no status byte (known)
        //   • storageInfoRes            — Digitakt always returns status=0 even on success;
        //                                 treat decoded[5] as the first payload byte so the
        //                                 response is forwarded and getStorageInfo() can
        //                                 inspect the values rather than failing immediately.
        //   • pingRes, deviceUIDRes     — status byte is actually device-type data, not 0/1.
        let noStatusByte: Set<ElektronMsgType> = [.listDirRes, .readChunkRes,
                                                  .storageInfoRes,
                                                  .pingRes, .deviceUIDRes]
        if parsed.isResponse && !noStatusByte.contains(parsed.msgType) && parsed.status == 0 {
            await mailbox.fail(type: parsed.msgType, with: ElektronError.deviceError(status: 0))
            return
        }
        await mailbox.receive(msgType: parsed.msgType, payload: parsed.payload)
    }

    // MARK: - DigitaktTransferProtocol

    func listFiles(remotePath: String) async throws -> [SampleFile] {
        let payload = [UInt8].asciiString(Self.digitaktPath(remotePath))
        let response = try await request(.listDirReq, payload: payload, expecting: .listDirRes)
        return ElektronSysEx.parseFileListing(response)
    }

    func uploadSample(
        localURL: URL,
        remotePath: String,
        progress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws {
        let fileData = try Data(contentsOf: localURL)

        // Convert WAV → Elektron internal format if needed.
        // The Digitakt stores samples as a 64-byte metadata header + big-endian PCM.
        let uploadData: Data
        if [UInt8](fileData.prefix(4)) == [0x52, 0x49, 0x46, 0x46],
           let elektron = Self.wavToElektronFormat(fileData) {
            uploadData = elektron
        } else {
            uploadData = fileData  // already Elektron format, pass through
        }
        let totalBytes = Int64(uploadData.count)

        // 1 — Open writer: payload = fileSize(4 BE) + path(null-terminated)
        var openPayload: [UInt8] = []
        openPayload.appendBE32(UInt32(uploadData.count))
        openPayload.append(contentsOf: [UInt8].asciiString(remotePath))
        let openWriteResp = try await request(.openWriterReq, payload: openPayload, expecting: .openWriterRes)
        guard let writeHandle = openWriteResp.readBE32(at: 0) else { throw ElektronError.invalidPayload }

        // 2 — Stream chunks
        // writeChunkReq payload: handle(4 BE) + chunkSize(4 BE) + byteOffset(4 BE) + data
        // (from elektroid source: id@[5], chunk_size@[9], offset@[13], no reserved field)
        let uploadBytes = [UInt8](uploadData)
        var offset: Int = 0
        var sent:   Int64 = 0
        while offset < uploadBytes.count {
            let end       = min(offset + writeChunkSize, uploadBytes.count)
            let chunkData = Array(uploadBytes[offset..<end])
            let chunkSize = chunkData.count

            var chunkPayload: [UInt8] = []
            chunkPayload.appendBE32(writeHandle)
            chunkPayload.appendBE32(UInt32(chunkSize))
            chunkPayload.appendBE32(UInt32(offset))
            chunkPayload.append(contentsOf: chunkData)

            _ = try await request(.writeChunkReq, payload: chunkPayload, expecting: .writeChunkRes)
            sent   += Int64(chunkSize)
            offset  = end
            let p = TransferProgress(bytesTransferred: min(sent, totalBytes), totalBytes: totalBytes)
            await MainActor.run { progress(p) }
        }

        // 3 — Close writer: handle(4 BE) + totalBytes(4 BE) — finalizes the file on device.
        // totalBytes must include the 64-byte Elektron header (matches openWriterReq size).
        var closePayload: [UInt8] = []
        closePayload.appendBE32(writeHandle)
        closePayload.appendBE32(UInt32(uploadData.count))
        _ = try await request(.closeWriterReq, payload: closePayload, expecting: .closeWriterRes)

        await MainActor.run {
            progress(TransferProgress(bytesTransferred: totalBytes, totalBytes: totalBytes))
        }
    }

    func downloadSample(
        remotePath: String,
        progress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws -> URL {
        // 1 — Open reader: payload = path(null-terminated)
        let openResp = try await request(
            .openReaderReq,
            payload: [UInt8].asciiString(remotePath),
            expecting: .openReaderRes
        )
        // openReaderRes payload: [0..3] = file handle (pass back in each readChunkReq),
        //                        [4..7] = actual file size in bytes.
        guard let handle    = openResp.readBE32(at: 0) else { throw ElektronError.invalidPayload }
        guard let totalSize = openResp.readBE32(at: 4) else { throw ElektronError.invalidPayload }
        guard totalSize > 0 else {
            let hex = openResp.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
            throw ElektronError.transferFailed("open reader size 0 for '\(remotePath)' — payload[\(openResp.count)]: \(hex)")
        }
        let totalBytes = Int64(totalSize)

        // 2 — Read chunks.
        // readChunkReq payload: handle(4 BE) + chunkSize(4 BE) + byteOffset(4 BE)
        // readChunkRes (status NOT stripped — readChunkRes is in noStatusByte):
        //   [0]=status [1..4]=handleEcho [5..8]=chunkSizeEcho [9..12]=offsetEcho
        //   [13..16]=cumulative bytes sent so far (NOT per-chunk size) [17+]=data
        //
        // byteOffset must be chunk-aligned (multiple of writeChunkSize).
        // Per-chunk data size = chunkResp.count - 17 (not the [13..16] field).
        var received = Data()
        var remaining = Int(totalBytes)
        var blockIndex: UInt32 = 0
        while remaining > 0 {
            let chunkSize = min(writeChunkSize, remaining)
            var readPayload: [UInt8] = []
            readPayload.appendBE32(handle)
            readPayload.appendBE32(UInt32(chunkSize))
            readPayload.appendBE32(blockIndex * UInt32(writeChunkSize))   // byte offset
            let chunkResp = try await request(
                .readChunkReq,
                payload: readPayload,
                expecting: .readChunkRes
            )
            // readChunkRes is in noStatusByte — status byte is payload[0], not stripped.
            // [0]=status [1-4]=handleEcho [5-8]=chunkSizeEcho [9-12]=offsetEcho
            // [13-16]=cumulative bytes sent so far (NOT per-chunk size) [17+]=data
            // status=0x00 means EOF — break gracefully.
            if chunkResp.first == 0x00 { break }
            let dataStart = 17
            let dataBytes = chunkResp.count - dataStart
            guard dataBytes > 0 else { break }
            received.append(contentsOf: chunkResp[dataStart..<dataStart + dataBytes])
            remaining -= dataBytes
            blockIndex += 1

            let p = TransferProgress(bytesTransferred: totalBytes - Int64(remaining), totalBytes: totalBytes)
            await MainActor.run { progress(p) }
        }

        // 3 — Close reader
        _ = try? await request(.closeReaderReq, payload: [], expecting: .closeReaderRes)

        // 4 — Convert to WAV and write to temp file.
        // The Digitakt stores samples in an internal format: a 64-byte metadata header
        // (containing sample rate at bytes 11-12 BE) followed by raw 16-bit signed PCM.
        // Wrap in a standard RIFF/WAV container so AVAudioFile can open it.
        var filename = URL(fileURLWithPath: remotePath).lastPathComponent
        if !filename.lowercased().hasSuffix(".wav") { filename += ".wav" }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        let fileBytes = [UInt8](received)
        let outData = fileBytes.prefix(4) == [0x52, 0x49, 0x46, 0x46]
            ? received
            : Self.elektronPCMtoWAV(fileBytes)
        try outData.write(to: dest)
        await MainActor.run {
            progress(TransferProgress(bytesTransferred: totalBytes, totalBytes: totalBytes))
        }
        return dest
    }

    // MARK: - Elektron PCM → WAV

    /// Wraps Digitakt-internal PCM data in a RIFF/WAV container.
    ///
    /// Observed Elektron internal format:
    ///   bytes 0-63   — 64-byte metadata header
    ///   bytes 10-11  — sample rate, big-endian UInt16 (0xBB80=48000, 0xAC44=44100)
    ///   bytes 64+    — raw 16-bit signed PCM, mono, big-endian
    /// WAV requires little-endian PCM, so each sample pair is byte-swapped.
    private static func elektronPCMtoWAV(_ fileData: [UInt8]) -> Data {
        let elektronHeaderSize = 64
        guard fileData.count > elektronHeaderSize else { return Data(fileData) }

        let sampleRate: UInt32
        if fileData.count >= 12 {
            let sr = (UInt32(fileData[10]) << 8) | UInt32(fileData[11])
            sampleRate = (sr == 44100 || sr == 48000) ? sr : 44100
        } else {
            sampleRate = 44100
        }
        let channels: UInt16    = 1
        let bitsPerSample: UInt16 = 16
        let blockAlign: UInt16  = channels * bitsPerSample / 8
        let byteRate: UInt32    = sampleRate * UInt32(blockAlign)

        // Byte-swap each 16-bit sample: Digitakt stores BE PCM, WAV needs LE PCM.
        var audio = Array(fileData[elektronHeaderSize...])
        var i = 0
        while i + 1 < audio.count { audio.swapAt(i, i + 1); i += 2 }

        // De-glitch: the Digitakt's 7-bit SysEx encoder occasionally emits a wrong
        // MSB accumulator bit, producing single-sample spikes or short bursts of
        // corruption (up to ~30 consecutive bad samples). Detection: entry jump > 20000
        // from a moderate-energy context (|prevVal| < 8000); forward scan finds where
        // signal returns within 5000 of prevVal; interpolate linearly across the burst.
        // samps is kept in sync so a second burst immediately after the first is caught.
        let sampleCount = audio.count / 2
        if sampleCount > 2 {
            var samps = [Int32](repeating: 0, count: sampleCount)
            for s in 0..<sampleCount {
                let lo = UInt16(audio[s * 2])
                let hi = UInt16(audio[s * 2 + 1])
                samps[s] = Int32(Int16(bitPattern: lo | (hi << 8)))
            }
            let entryThreshold: Int32 = 20_000
            let exitTolerance:  Int32 = 5_000
            let prevLevelMax:   Int32 = 8_000  // only de-glitch in moderate-energy sections
            let maxBurst              = 30
            var s = 1
            while s < sampleCount - 1 {
                let prevVal = samps[s - 1]
                let curVal  = samps[s]
                guard abs(prevVal) < prevLevelMax,
                      abs(curVal - prevVal) > entryThreshold else { s += 1; continue }
                var burstEnd = s + 1
                while burstEnd < min(s + maxBurst, sampleCount) {
                    if abs(samps[burstEnd] - prevVal) < exitTolerance { break }
                    burstEnd += 1
                }
                guard burstEnd < min(s + maxBurst, sampleCount) else { s += 1; continue }
                let exitVal = samps[burstEnd]
                let span    = Float(burstEnd - s + 1)
                for k in s..<burstEnd {
                    let t      = Float(k - s + 1) / span
                    let interp = Int16(clamping: Int32(Float(prevVal) * (1 - t) + Float(exitVal) * t))
                    samps[k]   = Int32(interp)
                    let bits   = UInt16(bitPattern: interp)
                    audio[k * 2]     = UInt8(bits & 0xFF)
                    audio[k * 2 + 1] = UInt8(bits >> 8)
                }
                s = burstEnd
            }
        }
        let audioLength = UInt32(audio.count)

        func le32(_ v: UInt32) -> [UInt8] {
            [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
        }
        func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }

        var hdr: [UInt8] = []
        hdr += [0x52, 0x49, 0x46, 0x46]   // "RIFF"
        hdr += le32(36 + audioLength)       // RIFF chunk size
        hdr += [0x57, 0x41, 0x56, 0x45]   // "WAVE"
        hdr += [0x66, 0x6D, 0x74, 0x20]   // "fmt "
        hdr += le32(16)                     // fmt chunk size
        hdr += le16(1)                      // PCM
        hdr += le16(channels)
        hdr += le32(sampleRate)
        hdr += le32(byteRate)
        hdr += le16(blockAlign)
        hdr += le16(bitsPerSample)
        hdr += [0x64, 0x61, 0x74, 0x61]   // "data"
        hdr += le32(audioLength)
        return Data(hdr) + Data(audio)
    }

    // MARK: - WAV → Elektron PCM

    /// Converts a RIFF/WAV file to Elektron internal format for upload to the Digitakt.
    ///
    /// Observed Elektron header layout (64 bytes, from hardware download):
    ///   [10-11]: sample rate, big-endian UInt16 (0xBB80=48000, 0xAC44=44100)
    ///   [16-19]: sample count, big-endian UInt32
    ///   [20]:    0x7F — volume/gain constant observed on all downloaded samples
    ///   all other bytes: 0x00
    private static func wavToElektronFormat(_ wavData: Data) -> Data? {
        let bytes = [UInt8](wavData)
        guard bytes.count >= 44,
              bytes[0] == 0x52, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x46,  // "RIFF"
              bytes[8] == 0x57, bytes[9] == 0x41, bytes[10] == 0x56, bytes[11] == 0x45  // "WAVE"
        else { return nil }

        var pos = 12
        var sampleRate: UInt32 = 44100
        var pcmOffset = 0
        var pcmLength = 0

        while pos + 8 <= bytes.count {
            let id        = Array(bytes[pos..<pos+4])
            let chunkSize = UInt32(bytes[pos+4])
                          | (UInt32(bytes[pos+5]) << 8)
                          | (UInt32(bytes[pos+6]) << 16)
                          | (UInt32(bytes[pos+7]) << 24)
            if id == [0x66, 0x6D, 0x74, 0x20] {  // "fmt "
                if pos + 16 <= bytes.count {
                    sampleRate = UInt32(bytes[pos+12])
                               | (UInt32(bytes[pos+13]) << 8)
                               | (UInt32(bytes[pos+14]) << 16)
                               | (UInt32(bytes[pos+15]) << 24)
                }
            } else if id == [0x64, 0x61, 0x74, 0x61] {  // "data"
                pcmOffset = pos + 8
                pcmLength = Int(chunkSize)
                break
            }
            pos += 8 + Int(chunkSize)
            if chunkSize % 2 != 0 { pos += 1 }  // word-align
        }

        guard pcmLength > 0, pcmOffset + pcmLength <= bytes.count else { return nil }

        // Byte-swap each 16-bit sample: WAV is LE, Digitakt expects BE.
        var audio = Array(bytes[pcmOffset..<pcmOffset + pcmLength])
        var i = 0
        while i + 1 < audio.count { audio.swapAt(i, i + 1); i += 2 }

        // Build 64-byte Elektron sample header.
        // Layout confirmed from elektroid source + hardware capture:
        //   [0]     type       = 0
        //   [1]     stereo     = 0 (mono) / 1 (stereo)
        //   [2-3]   rsvd0      = 0
        //   [4-7]   size       = PCM byte count, BE uint32
        //   [8-11]  rate       = sample rate, BE uint32
        //   [12-15] loop_start = 0 (no loop)
        //   [16-19] loop_end   = 0 (no loop)
        //   [20]    loop_type  = 0x7F (observed constant from hardware)
        //   [21-23] rsvd1      = 0
        //   [24-63] padding    = 0
        let pcmByteCount = UInt32(pcmLength)
        var hdr = [UInt8](repeating: 0, count: 64)
        // [4-7] PCM byte count
        hdr[4] = UInt8((pcmByteCount >> 24) & 0xFF)
        hdr[5] = UInt8((pcmByteCount >> 16) & 0xFF)
        hdr[6] = UInt8((pcmByteCount >> 8) & 0xFF)
        hdr[7] = UInt8(pcmByteCount & 0xFF)
        // [8-11] sample rate
        hdr[8]  = UInt8((sampleRate >> 24) & 0xFF)
        hdr[9]  = UInt8((sampleRate >> 16) & 0xFF)
        hdr[10] = UInt8((sampleRate >> 8) & 0xFF)
        hdr[11] = UInt8(sampleRate & 0xFF)
        // [20] loop_type
        hdr[20] = 0x7F

        return Data(hdr) + Data(audio)
    }

    func deleteFile(remotePath: String) async throws {
        _ = try await request(
            .deleteFileReq,
            payload: [UInt8].asciiString(remotePath),
            expecting: .deleteFileRes
        )
    }

    func getStorageInfo() async throws -> StorageInfo {
        let response = try await request(.storageInfoReq, payload: [], expecting: .storageInfoRes)
        guard let used  = response.readBE32(at: 0),
              let total = response.readBE32(at: 4) else { throw ElektronError.invalidPayload }
        // Digitakt firmware (tested) returns all-zero payload — it doesn't populate storage stats
        // via SysEx. Throw so ConnectionManager's fallback path takes over.
        guard total > 0 else { throw ElektronError.transferFailed("storage info unavailable") }
        return StorageInfo(usedBytes: Int64(used), totalBytes: Int64(total))
    }

    // MARK: - Path Normalisation
    //
    // listDirReq: "/" for root, no leading slash for subdirectories ("VEC1 Sounds")
    // File ops (openReaderReq, openWriterReq, deleteFileReq): full path with leading slash ("/VEC1 Sounds/KICK.wav")

    private static func digitaktPath(_ path: String) -> String {
        guard path != "/" else { return "/" }
        return path.hasPrefix("/") ? String(path.dropFirst()) : path
    }

    // MARK: - Internal Helpers

    private func nextSeq() -> UInt16 {
        let seq = seqCounter
        seqCounter &+= 1
        return seq
    }

    private func request(
        _ msgType: ElektronMsgType,
        payload: [UInt8],
        expecting responseType: ElektronMsgType
    ) async throws -> [UInt8] {
        let msg = ElektronSysEx.build(seq: nextSeq(), msgType: msgType, payload: payload)
        try sendSysEx(msg)
        return try await withElektronTimeout(defaultTimeout) {
            try await self.mailbox.next(type: responseType)
        }
    }

    private func sendSysEx(_ bytes: [UInt8]) throws {
        // Allocate a raw buffer large enough to hold the MIDIPacketList header
        // plus the full SysEx payload. Passing capacity:1 only allocated the
        // fixed MIDIPacket.data[256] field — not enough for chunk-sized SysEx.
        let bufferSize = MemoryLayout<MIDIPacketList>.size + bytes.count
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: bufferSize,
            alignment: MemoryLayout<MIDIPacketList>.alignment
        )
        defer { raw.deallocate() }
        let listPtr = raw.assumingMemoryBound(to: MIDIPacketList.self)
        var pkt = MIDIPacketListInit(listPtr)
        bytes.withUnsafeBytes { buf in
            pkt = MIDIPacketListAdd(listPtr, bufferSize, pkt, 0, bytes.count, buf.baseAddress!)
        }
        guard pkt != nil else { throw ElektronError.transferFailed("MIDIPacketList buffer overflow") }
        let status = MIDISend(outputPort, device.destination, listPtr)
        guard status == noErr else { throw ElektronError.transferFailed("MIDISend \(status)") }
    }
}
