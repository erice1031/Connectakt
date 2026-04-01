import AVFoundation

final class ConnectaktAudioUnit: AUAudioUnit, @unchecked Sendable {
    private var inputBus: AUAudioUnitBus!
    private var outputBus: AUAudioUnitBus!
    private var inputBusArray: AUAudioUnitBusArray!
    private var outputBusArray: AUAudioUnitBusArray!
    private var maximumFrameCount: AUAudioFrameCount = 4096
    private var bypassed = false

    override init(componentDescription: AudioComponentDescription, options: AudioComponentInstantiationOptions) throws {
        try super.init(componentDescription: componentDescription, options: options)

        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        inputBus = try AUAudioUnitBus(format: format)
        outputBus = try AUAudioUnitBus(format: format)
        inputBus.maximumChannelCount = 2
        outputBus.maximumChannelCount = 2
        inputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
        outputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
    }

    override var inputBusses: AUAudioUnitBusArray { inputBusArray }
    override var outputBusses: AUAudioUnitBusArray { outputBusArray }
    override var canProcessInPlace: Bool { true }

    override var channelCapabilities: [NSNumber] {
        [2, 2]
    }

    override var maximumFramesToRender: AUAudioFrameCount {
        get { maximumFrameCount }
        set { maximumFrameCount = newValue }
    }

    override var shouldBypassEffect: Bool {
        get { bypassed }
        set { bypassed = newValue }
    }

    override func allocateRenderResources() throws {
        let inputChannels = inputBusses[0].format.channelCount
        let outputChannels = outputBusses[0].format.channelCount
        guard inputChannels == outputChannels else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_FormatNotSupported))
        }

        try super.allocateRenderResources()
    }

    override var internalRenderBlock: AUInternalRenderBlock {
        { actionFlags, timestamp, frameCount, outputBusNumber, outputData, realtimeEventListHead, pullInputBlock in
            guard let pullInputBlock else { return kAudioUnitErr_NoConnection }
            return pullInputBlock(actionFlags, timestamp, frameCount, 0, outputData)
        }
    }
}
