import Testing
@testable import Connectakt

// MARK: - Connection Manager Tests

@Suite("ConnectionManager")
struct ConnectionManagerTests {

    @Test("Initial state is disconnected")
    func initialStateIsDisconnected() {
        let manager = ConnectionManager()
        #expect(manager.status == .disconnected)
        #expect(manager.samples.isEmpty)
        #expect(manager.usedStorageBytes == 0)
    }

    @Test("Disconnect resets all state")
    func disconnectResetsState() async {
        let manager = ConnectionManager()
        manager.simulateConnect()
        // Give the async task a moment (it has an 800ms delay, so we just test post-disconnect)
        manager.disconnect()
        #expect(manager.status == .disconnected)
        #expect(manager.samples.isEmpty)
        #expect(manager.usedStorageBytes == 0)
    }

    @Test("Storage percent calculates correctly")
    func storagePercentCalculation() {
        let manager = ConnectionManager()
        // Total is 700MB, used is 0 → 0%
        #expect(manager.storagePercent == 0.0)
    }

    @Test("SampleFile size string formats correctly")
    func sampleFileSizeStringKB() {
        let smallFile = SampleFile(name: "TINY.WAV", size: 512_000, isFolder: false)
        // 512,000 bytes = ~500 KB
        #expect(smallFile.sizeString.contains("KB"))
    }

    @Test("SampleFile size string formats MB correctly")
    func sampleFileSizeStringMB() {
        let bigFile = SampleFile(name: "BIG.WAV", size: 2_097_152, isFolder: false)
        // 2,097,152 bytes = exactly 2.0 MB
        #expect(bigFile.sizeString == "2.0 MB")
    }
}

// MARK: - Connection Status Tests

@Suite("ConnectionStatus")
struct ConnectionStatusTests {

    @Test("Disconnected is not connected")
    func disconnectedIsNotConnected() {
        #expect(ConnectionStatus.disconnected.isConnected == false)
    }

    @Test("Connected is connected")
    func connectedIsConnected() {
        #expect(ConnectionStatus.connected(deviceName: "DIGITAKT").isConnected == true)
    }

    @Test("Scanning is not connected")
    func scanningIsNotConnected() {
        #expect(ConnectionStatus.scanning.isConnected == false)
    }

    @Test("Connected label is uppercased device name")
    func connectedLabel() {
        let status = ConnectionStatus.connected(deviceName: "digitakt")
        #expect(status.label == "DIGITAKT")
    }

    @Test("Disconnected label is NO DEVICE")
    func disconnectedLabel() {
        #expect(ConnectionStatus.disconnected.label == "NO DEVICE")
    }
}
