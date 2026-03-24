import CoreMIDI
import Foundation

// MARK: - Elektron MIDI Transfer
//
// Full DigitaktTransferProtocol implementation via CoreMIDI + Elektron SysEx.
// Works on iOS and macOS — USB MIDI is class-compliant, no MFi required.
//
// Design: serial request/response. An actor-based mailbox decouples the CoreMIDI
// read callback (which fires on a non-Swift-concurrency thread) from async callers.

// MARK: - Mailbox Actor

private actor ElektronMailbox {
    typealias MsgType = ElektronMsgType

    // Received messages not yet claimed by a waiter
    private var buffer: [(MsgType, [UInt8])] = []

    // Waiters for a specific single type
    private var waiters: [(UInt8, CheckedContinuation<[UInt8], Error>)] = []

    // Waiters that accept any one of a set of types (first match wins)
    private var multiWaiters: [(Set<UInt8>, CheckedContinuation<(MsgType, [UInt8]), Error>)] = []

    // MARK: - Receive (called from MIDI callback via Task)

    func receive(msgType: MsgType, payload: [UInt8]) {
        let raw = msgType.rawValue

        // Satisfy a single-type waiter first
        if let idx = waiters.firstIndex(where: { $0.0 == raw }) {
            let (_, cont) = waiters.remove(at: idx)
            cont.resume(returning: payload)
            return
        }

        // Satisfy a multi-type waiter
        if let idx = multiWaiters.firstIndex(where: { $0.0.contains(raw) }) {
            let (_, cont) = multiWaiters.remove(at: idx)
            cont.resume(returning: (msgType, payload))
            return
        }

        // Park in buffer for future claim
        buffer.append((msgType, payload))
    }

    // MARK: - Await one type

    func next(type: MsgType, timeout: TimeInterval = 5) async throws -> [UInt8] {
        let raw = type.rawValue
        if let idx = buffer.firstIndex(where: { $0.0.rawValue == raw }) {
            return buffer.remove(at: idx).1
        }
        return try await withCheckedThrowingContinuation { cont in
            waiters.append((raw, cont))
        }
    }

    // MARK: - Await any of a set of types

    func nextAny(
        of types: ElektronMsgType...,
        timeout: TimeInterval = 10
    ) async throws -> (ElektronMsgType, [UInt8]) {
        let rawSet = Set(types.map(\.rawValue))
        if let idx = buffer.firstIndex(where: { rawSet.contains($0.0.rawValue) }) {
            return buffer.remove(at: idx)
        }
        return try await withCheckedThrowingContinuation { cont in
            multiWaiters.append((rawSet, cont))
        }
    }

    // MARK: - Abort all pending waiters

    func abortAll(with error: Error) {
        for (_, cont) in waiters { cont.resume(throwing: error) }
        waiters.removeAll()
        for (_, cont) in multiWaiters { cont.resume(throwing: error) }
        multiWaiters.removeAll()
        buffer.removeAll()
    }
}

// MARK: - ElektronMIDITransfer

final class ElektronMIDITransfer: DigitaktTransferProtocol {

    private let device: ElektronDeviceInfo
    private let mailbox = ElektronMailbox()

    private var midiClient: MIDIClientRef = 0
    private var outputPort: MIDIPortRef = 0
    private var inputPort: MIDIPortRef = 0

    private let defaultTimeout: TimeInterval = 5
    private let chunkSize = 48   // bytes per SysEx write-chunk (well within MIDI buffer)

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
                        let data = withUnsafePointer(to: pkt.pointee.data) { dataPtr in
                            Data(UnsafeRawBufferPointer(start: dataPtr, count: length))
                        }
                        Task { await self.handleIncomingData(data) }
                    }
                    pkt = UnsafePointer(MIDIPacketNext(UnsafeMutablePointer(mutating: pkt)))
                }
            }
        }

        var status = MIDIClientCreate("ConnektaktTransfer" as CFString, nil, nil, &midiClient)
        guard status == noErr else { throw ElektronError.transferFailed("MIDI client err \(status)") }

        status = MIDIOutputPortCreate(midiClient, "ConnektaktOut" as CFString, &outputPort)
        guard status == noErr else { throw ElektronError.transferFailed("output port err \(status)") }

        status = MIDIInputPortCreateWithBlock(midiClient, "ConnektaktIn" as CFString, &inputPort, readBlock)
        guard status == noErr else { throw ElektronError.transferFailed("input port err \(status)") }

        MIDIPortConnectSource(inputPort, device.source, nil)
    }

    // MARK: - DigitaktTransferProtocol

    func listFiles(remotePath: String) async throws -> [SampleFile] {
        let response = try await request(.listDirReq,
                                        payload: [UInt8].asciiString(remotePath),
                                        expecting: .listDirRes)
        return parseFileListing(response)
    }

    func uploadSample(
        localURL: URL,
        remotePath: String,
        progress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws {
        let fileData = try Data(contentsOf: localURL)
        let totalBytes = Int64(fileData.count)

        // 1. Initiate write
        var req = [UInt8].asciiString(remotePath)
        req.appendLE32(UInt32(totalBytes))
        _ = try await request(.writeFileReq, payload: req, expecting: .writeFileAck)

        // 2. Send chunks
        var offset = 0
        var sent: Int64 = 0
        while offset < fileData.count {
            let end = min(offset + chunkSize, fileData.count)
            let chunk = [UInt8](fileData[offset..<end])
            try sendSysEx(ElektronSysEx.build(msgType: .writeFileChunk, payload: chunk))
            sent += Int64(chunk.count)
            offset = end
            let p = TransferProgress(bytesTransferred: min(sent, totalBytes), totalBytes: totalBytes)
            await MainActor.run { progress(p) }
        }

        // 3. Finalise
        _ = try await request(.writeFileEnd, payload: [], expecting: .writeFileAck)
        await MainActor.run {
            progress(TransferProgress(bytesTransferred: totalBytes, totalBytes: totalBytes))
        }
    }

    func downloadSample(
        remotePath: String,
        progress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws -> URL {
        // 1. Request file — device sends readFileBegin + N readFileChunk + readFileEnd
        try sendSysEx(ElektronSysEx.build(msgType: .readFileReq,
                                          payload: [UInt8].asciiString(remotePath)))

        let beginPayload = try await mailbox.next(type: .readFileBegin)
        guard let totalSize = beginPayload.readLE32(at: 0) else { throw ElektronError.invalidPayload }
        let totalBytes = Int64(totalSize)

        // 2. Collect chunks
        var received = Data()
        while true {
            let (type, chunk) = try await mailbox.nextAny(of: .readFileChunk, .readFileEnd)
            if type == .readFileEnd { break }
            received.append(contentsOf: chunk)
            let p = TransferProgress(bytesTransferred: Int64(received.count), totalBytes: totalBytes)
            await MainActor.run { progress(p) }
        }

        // 3. Write to temp
        let filename = URL(fileURLWithPath: remotePath).lastPathComponent
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try received.write(to: dest)
        await MainActor.run {
            progress(TransferProgress(bytesTransferred: totalBytes, totalBytes: totalBytes))
        }
        return dest
    }

    func deleteFile(remotePath: String) async throws {
        _ = try await request(.deleteFileReq,
                              payload: [UInt8].asciiString(remotePath),
                              expecting: .deleteFileRes)
    }

    func getStorageInfo() async throws -> StorageInfo {
        let response = try await request(.storageInfoReq, payload: [], expecting: .storageInfoRes)
        guard let used  = response.readLE32(at: 0),
              let total = response.readLE32(at: 4) else { throw ElektronError.invalidPayload }
        return StorageInfo(usedBytes: Int64(used), totalBytes: Int64(total))
    }

    // MARK: - Internal Helpers

    private func request(
        _ msgType: ElektronMsgType,
        payload: [UInt8],
        expecting responseType: ElektronMsgType
    ) async throws -> [UInt8] {
        try sendSysEx(ElektronSysEx.build(msgType: msgType, payload: payload))
        return try await withTimeout(defaultTimeout) {
            try await self.mailbox.next(type: responseType)
        }
    }

    private func sendSysEx(_ bytes: [UInt8]) throws {
        var b = bytes
        let listPtr = UnsafeMutablePointer<MIDIPacketList>.allocate(capacity: 1)
        defer { listPtr.deallocate() }
        var pkt = MIDIPacketListInit(listPtr)
        pkt = MIDIPacketListAdd(listPtr, 65536, pkt, 0, b.count, &b)
        let status = MIDISend(outputPort, device.destination, listPtr)
        guard status == noErr else { throw ElektronError.transferFailed("MIDISend \(status)") }
    }

    private func handleIncomingData(_ data: Data) async {
        guard data.count >= 2, data[0] == 0xF0 else { return }
        guard let parsed = ElektronSysEx.parse(data) else { return }
        if parsed.msgType == .error {
            await mailbox.abortAll(with: ElektronError.transferFailed("DEVICE RETURNED ERROR"))
            return
        }
        await mailbox.receive(msgType: parsed.msgType, payload: parsed.payload)
    }

    // MARK: - File Listing Parser

    private func parseFileListing(_ payload: [UInt8]) -> [SampleFile] {
        var files = [SampleFile]()
        var offset = 0
        while offset < payload.count {
            guard let (name, next) = payload.readCString(at: offset),
                  !name.isEmpty,
                  let size = payload.readLE32(at: next) else { break }
            let isDir = name.hasSuffix("/")
            files.append(SampleFile(
                name: isDir ? String(name.dropLast()) : name,
                size: Int64(size),
                isFolder: isDir
            ))
            offset = next + 4
        }
        return files
    }
}

// MARK: - Timeout helper

private func withTimeout<T: Sendable>(
    _ seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw ElektronError.noResponse(timeout: seconds)
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
