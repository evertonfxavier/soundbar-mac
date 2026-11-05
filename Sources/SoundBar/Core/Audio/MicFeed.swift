import CoreAudio
import Foundation

/// Reads the real microphone, adds the playing sounds (`VoiceMixer`) and writes the result to the virtual
/// microphone, so the app of the call, which listens to the virtual one, hears the voice and the sounds.
///
/// One private aggregate device holds both: [real microphone, virtual microphone], in that order, because the
/// streams of an aggregate follow the order of its list. The IOProc takes the real microphone's input stream and
/// writes the virtual device's output stream; the other streams (the real device's output, the virtual device's
/// loopback input) are not used. The virtual device is the clock; the microphone is drift compensated to it.
final class MicFeed {
    enum FeedError: LocalizedError {
        case deviceMissing
        case coreAudio(L, OSStatus)

        var errorDescription: String? {
            switch self {
            case .deviceMissing: L.errDeviceMissing.string
            case .coreAudio(let what, let status): L.errStepFailed.formatted(what.string, String(status))
            }
        }
    }

    let micUID: String
    let virtualUID: String
    /// The rate the aggregate runs at, which is the rate the sounds are decoded for.
    private(set) var sampleRate: Double = 48_000

    private let mixer: VoiceMixer
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "soundbar.micfeed", qos: .userInteractive)

    init(micUID: String, virtualUID: String, mixer: VoiceMixer) throws {
        self.micUID = micUID
        self.virtualUID = virtualUID
        self.mixer = mixer
        do {
            try start()
        } catch {
            stop()
            throw error
        }
    }

    deinit { stop() }

    private func start() throws {
        guard let mic = CA.device(forUID: micUID), let virtual = CA.device(forUID: virtualUID) else {
            throw FeedError.deviceMissing
        }

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "SoundBar Feed",
            kAudioAggregateDeviceUIDKey: "soundbar-feed-\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: virtualUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: micUID, kAudioSubDeviceDriftCompensationKey: true],
                [kAudioSubDeviceUIDKey: virtualUID],
            ],
        ]
        var status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID)
        guard status == noErr else { throw FeedError.coreAudio(.stepCreateAggregate, status) }

        sampleRate = CA.get(aggregateID, kAudioDevicePropertyNominalSampleRate, initial: Float64(0)) ?? 0
        if sampleRate <= 0 { sampleRate = 48_000 }

        let micInputStreams = CA.streamCount(mic, input: true)
        let micOutputStreams = CA.streamCount(mic, input: false)
        let virtualOutputStreams = CA.streamCount(virtual, input: false)
        guard micInputStreams > 0, virtualOutputStreams > 0 else { throw FeedError.deviceMissing }

        let mixer = self.mixer
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, input, _, output, _ in
            MicFeed.render(
                input: UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)),
                output: UnsafeMutableAudioBufferListPointer(output),
                outputStart: micOutputStreams, mixer: mixer)
        }
        guard status == noErr else { throw FeedError.coreAudio(.stepCreateIOProc, status) }

        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else { throw FeedError.coreAudio(.stepStartAudio, status) }
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        procID = nil
    }

    // MARK: - Realtime render (no allocations, no locks that wait)

    /// `input` is the list of the aggregate's input streams, whose first stream is the real microphone's; in
    /// `output`, the streams from `outputStart` on are the virtual microphone's. Everything in `output` is silenced,
    /// then the microphone (a mono one in both channels) and the sounds go into the first two channels of the virtual
    /// stream.
    static func render(
        input: UnsafeMutableAudioBufferListPointer, output: UnsafeMutableAudioBufferListPointer,
        outputStart: Int, mixer: VoiceMixer
    ) {
        for buffer in output {
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }
        guard outputStart < output.count, let outData = output[outputStart].mData else { return }
        let outChannels = Int(output[outputStart].mNumberChannels)
        guard outChannels > 0 else { return }
        let outFrames = Int(output[outputStart].mDataByteSize) / (MemoryLayout<Float>.size * outChannels)
        let out = outData.assumingMemoryBound(to: Float.self)

        if input.count > 0, let inData = input[0].mData {
            let inChannels = Int(input[0].mNumberChannels)
            if inChannels > 0 {
                let inFrames = Int(input[0].mDataByteSize) / (MemoryLayout<Float>.size * inChannels)
                let micSamples = inData.assumingMemoryBound(to: Float.self)
                for frame in 0..<min(outFrames, inFrames) {
                    let left = micSamples[frame * inChannels]
                    let right = inChannels > 1 ? micSamples[frame * inChannels + 1] : left
                    out[frame * outChannels] = left
                    if outChannels > 1 { out[frame * outChannels + 1] = right }
                }
            }
        }

        mixer.render(into: out, frames: outFrames, channels: outChannels)
    }
}
