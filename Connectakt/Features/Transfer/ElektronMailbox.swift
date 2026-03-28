import Foundation

// MARK: - Elektron Mailbox Actor
//
// Decouples MIDI callback / USB read threads from async protocol callers.
// Supports awaiting a single expected message type or any of a set of types.
// Shared by ElektronMIDITransfer and ElektronUSBTransfer.

actor ElektronMailbox {
    typealias MsgType = ElektronMsgType

    private var buffer:      [(MsgType, [UInt8])] = []
    private var waiters:     [(UInt8, CheckedContinuation<[UInt8], Error>)] = []
    private var multiWaiters:[(Set<UInt8>, CheckedContinuation<(MsgType, [UInt8]), Error>)] = []

    // MARK: - Receive (called from I/O callback via Task)

    func receive(msgType: MsgType, payload: [UInt8]) {
        let raw = msgType.rawValue
        if let idx = waiters.firstIndex(where: { $0.0 == raw }) {
            waiters.remove(at: idx).1.resume(returning: payload)
            return
        }
        if let idx = multiWaiters.firstIndex(where: { $0.0.contains(raw) }) {
            multiWaiters.remove(at: idx).1.resume(returning: (msgType, payload))
            return
        }
        buffer.append((msgType, payload))
    }

    // MARK: - Await one type

    func next(type: MsgType) async throws -> [UInt8] {
        let raw = type.rawValue
        if let idx = buffer.firstIndex(where: { $0.0.rawValue == raw }) {
            return buffer.remove(at: idx).1
        }
        return try await withCheckedThrowingContinuation { cont in
            waiters.append((raw, cont))
        }
    }

    // MARK: - Await any of a set of types

    func nextAny(of types: ElektronMsgType...) async throws -> (ElektronMsgType, [UInt8]) {
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
        waiters.forEach     { $0.1.resume(throwing: error) }
        multiWaiters.forEach{ $0.1.resume(throwing: error) }
        waiters.removeAll()
        multiWaiters.removeAll()
        buffer.removeAll()
    }
}

// MARK: - Timeout helper

/// Races `operation` against a timeout; throws `ElektronError.noResponse` if the timeout fires first.
func withElektronTimeout<T: Sendable>(
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
