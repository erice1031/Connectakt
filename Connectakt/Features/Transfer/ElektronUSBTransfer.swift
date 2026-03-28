#if os(macOS)
import Foundation

// MARK: - ElektronUSBTransfer (macOS only)
//
// DigitaktTransferProtocol implementation using the Digitakt's vendor-specific
// USB bulk interface (IOUSBHostTransport). This is the preferred path when the
// Digitakt exposes a class-0xFF interface; falls back to ElektronMIDITransfer
// when only MIDI class interfaces are present (current Digitakt firmware).
//
// Wire format: identical to ElektronMIDITransfer — 7-bit-encoded SysEx with
// 6-byte header {F0 00 20 3C 10 00} — sent directly over USB bulk endpoints
// without any USB MIDI 1.0 packet framing overhead.
//
// Reference: Elektroid (https://github.com/dagargo/elektroid)

final class ElektronUSBTransfer: DigitaktTransferProtocol {

    private let transport   = IOUSBHostTransport()
    private let mailbox     = ElektronMailbox()
    private var readTask:   Task<Void, Never>?

    private var seqCounter: UInt16 = 0
    private let writeChunkSize = 0x2000
    private let defaultTimeout: TimeInterval = 10

    // MARK: - Init / Deinit

    init() throws {
        try transport.open()
        startReadLoop()
    }

    deinit {
        readTask?.cancel()
        transport.close()
    }

    // MARK: - Background USB Read Loop
    //
    // Reads continuously from the bulk IN pipe. Reassembles complete SysEx frames
    // (F0…F7) from the byte stream and dispatches them to the mailbox.

    private func startReadLoop() {
        readTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            var assembly = Data()

            while !Task.isCancelled {
                do {
                    let chunk = try self.transport.receive(maxLength: 65_536, timeout: 2.0)
                    if !chunk.isEmpty {
                        assembly.append(chunk)
                        assembly = await self.drainSysEx(from: assembly)
                    }
                } catch let err as IOUSBHostTransport.USBTransportError where err == .notOpen {
                    break
                } catch {
                    // 2-second receive timeout fires naturally — keep looping
                }
            }
        }
    }

    private func drainSysEx(from buffer: Data) async -> Data {
        var buf = buffer
        while let f0 = buf.firstIndex(of: 0xF0),
              let f7 = buf[f0...].firstIndex(of: 0xF7) {
            let frame = buf[f0...f7]
            await handleFrame(Data(frame))
            buf.removeSubrange(buf.startIndex...f7)
        }
        if buf.count > 1_048_576 { buf.removeAll() }
        return buf
    }

    private func handleFrame(_ data: Data) async {
        guard let parsed = ElektronSysEx.parse(data) else { return }
        if parsed.msgType == .error {
            await mailbox.abortAll(with: ElektronError.deviceError(status: parsed.status))
            return
        }
        await mailbox.receive(msgType: parsed.msgType, payload: parsed.payload)
    }

    // MARK: - DigitaktTransferProtocol

    func listFiles(remotePath: String) async throws -> [SampleFile] {
        let payload  = [UInt8].asciiString(remotePath)
        let response = try await request(.listDirReq, payload: payload, expecting: .listDirRes)
        return ElektronSysEx.parseFileListing(response)
    }

    func uploadSample(
        localURL: URL,
        remotePath: String,
        progress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws {
        let fileData   = try Data(contentsOf: localURL)
        let totalBytes = Int64(fileData.count)

        // 1 — Open writer
        var openPayload: [UInt8] = []
        openPayload.appendBE32(UInt32(fileData.count))
        openPayload.append(contentsOf: [UInt8].asciiString(remotePath))
        _ = try await request(.openWriterReq, payload: openPayload, expecting: .openWriterRes)

        // 2 — Stream chunks
        var offset: Int = 0
        var sent:   Int64 = 0
        while offset < fileData.count {
            let end       = min(offset + writeChunkSize, fileData.count)
            let chunkData = [UInt8](fileData[offset..<end])

            var chunkPayload: [UInt8] = []
            chunkPayload.appendBE32(UInt32(offset))
            chunkPayload.appendBE32(UInt32(chunkData.count))
            chunkPayload.appendBE32(0)
            chunkPayload.append(contentsOf: chunkData)

            _ = try await request(.writeChunkReq, payload: chunkPayload, expecting: .writeChunkRes)
            sent   += Int64(chunkData.count)
            offset  = end
            let p = TransferProgress(bytesTransferred: min(sent, totalBytes), totalBytes: totalBytes)
            await MainActor.run { progress(p) }
        }

        await MainActor.run {
            progress(TransferProgress(bytesTransferred: totalBytes, totalBytes: totalBytes))
        }
    }

    func downloadSample(
        remotePath: String,
        progress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws -> URL {
        // 1 — Open reader
        let openResp = try await request(
            .openReaderReq,
            payload: [UInt8].asciiString(remotePath),
            expecting: .openReaderRes
        )
        guard let totalSize = openResp.readBE32(at: 0) else { throw ElektronError.invalidPayload }
        let totalBytes = Int64(totalSize)

        // 2 — Read chunks
        var received = Data()
        var offset: Int = 0
        while Int64(offset) < totalBytes {
            let chunkSize = min(writeChunkSize, Int(totalBytes) - offset)
            var readPayload: [UInt8] = []
            readPayload.appendBE32(UInt32(offset))
            readPayload.appendBE32(UInt32(chunkSize))
            readPayload.appendBE32(0)

            let chunkResp = try await request(.readChunkReq, payload: readPayload, expecting: .readChunkRes)
            received.append(contentsOf: chunkResp)
            offset += chunkResp.count

            let p = TransferProgress(bytesTransferred: Int64(received.count), totalBytes: totalBytes)
            await MainActor.run { progress(p) }
        }

        // 3 — Close reader
        _ = try? await request(.closeReaderReq, payload: [], expecting: .closeReaderRes)

        // 4 — Write to temp file
        let filename = URL(fileURLWithPath: remotePath).lastPathComponent
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try received.write(to: dest)
        await MainActor.run {
            progress(TransferProgress(bytesTransferred: totalBytes, totalBytes: totalBytes))
        }
        return dest
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
        return StorageInfo(usedBytes: Int64(used), totalBytes: Int64(total))
    }

    // MARK: - Helpers

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
        try transport.send(Data(msg))
        return try await withElektronTimeout(defaultTimeout) {
            try await self.mailbox.next(type: responseType)
        }
    }
}
#endif
