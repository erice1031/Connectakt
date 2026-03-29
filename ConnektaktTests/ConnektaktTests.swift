import Testing
import Foundation
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

// MARK: - Sample Editor Tests

@Suite("SampleEditorProcessor")
struct SampleEditorProcessorTests {

    @Test("Processed samples apply trim reverse fade and normalize")
    func processedSamplesApplyEditStack() {
        let source: [Float] = [0, 0.25, 0.5, 1.0, 0.5, 0.25, 0]
        let settings = EditorEditSettings(
            trimStart: 1,
            trimEnd: 6,
            fadeInDuration: 2,
            fadeOutDuration: 2,
            normalize: true,
            reverse: true,
            pitchSemitones: 0,
            timeStretchRatio: 1,
            zoom: 1
        )

        let edited = SampleEditorProcessor.processedSamples(
            samples: source,
            sampleRate: 1,
            settings: settings
        )

        #expect(edited.count == 5)
        #expect(abs(edited[0]) < 0.0001)
        #expect(abs(edited[edited.count - 1]) < 0.0001)
        if let peak = edited.map({ abs($0) }).max() {
            #expect(peak <= 0.991)
            #expect(peak >= 0.98)
        }
    }

    @Test("Waveform peaks normalize into zero to one range")
    func waveformPeaksNormalize() {
        let peaks = SampleEditorProcessor.makePeaks(from: [0, -1, 0.25, 0.5, -0.75, 0], bucketCount: 3)
        #expect(peaks.count == 3)
        if let maxPeak = peaks.max() {
            #expect(abs(maxPeak - 1.0) < 0.0001)
        }
        #expect(peaks.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    @Test("Key estimation identifies an A tone")
    func keyEstimationDetectsA() async {
        let sampleRate = 44_100.0
        let frameCount = 16_384
        let samples = (0..<frameCount).map { index in
            let phase = 2.0 * Double.pi * 440.0 * Double(index) / sampleRate
            return Float(Darwin.sin(phase))
        }

        let key = await SampleEditorProcessor.estimateKeyName(samples: samples, sampleRate: sampleRate)
        #expect(key == "A")
    }
}

@Suite("EditorEffectChain")
struct EditorEffectChainTests {

    @Test("Effect chain state round-trips through codable")
    func effectChainRoundTrip() throws {
        let descriptor = EditorEffectDescriptor(
            name: "Tape Echo",
            manufacturerName: "Acme Audio",
            componentType: 1_633_844_853,
            componentSubType: 1_702_393_768,
            componentManufacturer: 1_094_926_916
        )
        let original = EditorEffectChainState(items: [
            EditorEffectChainItem(
                descriptor: descriptor,
                parameterSnapshots: [
                    EditorEffectParameterSnapshot(address: 100, identifier: "mix", value: 0.75)
                ]
            ),
            EditorEffectChainItem(descriptor: descriptor, isBypassed: true)
        ])

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EditorEffectChainState.self, from: data)

        #expect(decoded == original)
        #expect(decoded.activeItems.count == 1)
        #expect(decoded.items.first?.parameterSnapshots.first?.value == 0.75)
    }

    @Test("Preset store upserts by name and deletes by id")
    func presetStoreUpsertAndDelete() {
        let suiteName = "EditorEffectChainTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let descriptor = EditorEffectDescriptor(
            name: "Filter",
            manufacturerName: "Acme Audio",
            componentType: 1_633_844_853,
            componentSubType: 1_717_986_912,
            componentManufacturer: 1_094_926_916
        )
        let chain = EditorEffectChainState(items: [EditorEffectChainItem(descriptor: descriptor)])

        let first = EditorEffectPreset(name: "Drive Chain", chain: chain)
        let afterInsert = EditorEffectPresetStore.upsert(preset: first, existing: [], userDefaults: defaults)
        #expect(afterInsert.count == 1)

        let replacement = EditorEffectPreset(name: "Drive Chain", chain: EditorEffectChainState(items: []))
        let afterReplace = EditorEffectPresetStore.upsert(preset: replacement, existing: afterInsert, userDefaults: defaults)
        #expect(afterReplace.count == 1)
        #expect(afterReplace.first?.id == replacement.id)

        let afterDelete = EditorEffectPresetStore.delete(id: replacement.id, existing: afterReplace, userDefaults: defaults)
        #expect(afterDelete.isEmpty)
    }
}
