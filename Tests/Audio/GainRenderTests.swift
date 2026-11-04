import CoreAudio
import Foundation
import Testing

/// Audio buffers the way the system hands them to an IOProc: a list of streams, each one interleaved.
private final class Streams {
    let list: UnsafeMutableAudioBufferListPointer
    private let storage: [UnsafeMutablePointer<Float>]

    /// `streams[i]` holds the interleaved samples of stream `i`, which has `channels` channels.
    init(_ streams: [(channels: Int, samples: [Float])]) {
        // the list needs room for one buffer even when it is to hold none
        list = AudioBufferList.allocate(maximumBuffers: max(streams.count, 1))
        list.count = streams.count
        var pointers: [UnsafeMutablePointer<Float>] = []
        for (index, stream) in streams.enumerated() {
            let pointer = UnsafeMutablePointer<Float>.allocate(capacity: max(stream.samples.count, 1))
            pointer.initialize(from: stream.samples, count: stream.samples.count)
            pointers.append(pointer)
            list[index] = AudioBuffer(
                mNumberChannels: UInt32(stream.channels),
                mDataByteSize: UInt32(stream.samples.count * MemoryLayout<Float>.size),
                mData: pointer)
        }
        storage = pointers
    }

    deinit {
        for pointer in storage { pointer.deallocate() }
        free(list.unsafeMutablePointer)
    }

    func samples(_ stream: Int = 0) -> [Float] {
        let buffer = list[stream]
        let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        return Array(UnsafeBufferPointer(start: buffer.mData?.assumingMemoryBound(to: Float.self), count: count))
    }
}

/// The realtime heart of the app: what `AppTap` plays is the tapped audio times a gain, limited to full scale.
@Suite("AppTap.render")
struct GainRenderTests {
    /// Renders `input` (stereo, interleaved) into a stereo output of the same length.
    private func render(
        _ input: [Float], channels: Int = 2, outputChannels: Int = 2, current: Float = 1, target: Float = 1,
        inputStart: Int = 0, before: [(channels: Int, samples: [Float])] = []
    ) -> [Float] {
        let frames = input.count / channels
        let source = Streams(before + [(channels, input)])
        let output = Streams([(outputChannels, [Float](repeating: 7, count: frames * outputChannels))])
        let gain = GainState(current)
        gain.target = target

        AppTap.render(input: source.list, inputStart: inputStart, output: output.list, gain: gain)
        return output.samples()
    }

    @Test("at gain 1 the audio goes through untouched")
    func unity() {
        let audio: [Float] = [0.1, -0.2, 0.3, -0.4]

        #expect(render(audio) == audio)
    }

    @Test("the gain scales the audio, left and right alike")
    func scales() {
        let result = render([0.4, -0.8, 0.2, 0.6], current: 0.5, target: 0.5)

        #expect(result == [0.2, -0.4, 0.1, 0.3])
    }

    @Test("a muted app (gain 0) is silence")
    func muted() {
        #expect(render([0.5, -0.5, 0.9, 0.9], current: 0, target: 0) == [0, 0, 0, 0])
    }

    @Test("a boost is limited to full scale instead of wrapping around")
    func limitsToFullScale() {
        let result = render([0.9, -0.9, 0.5, -0.5], current: 1.5, target: 1.5)

        #expect(result == [1, -1, 0.75, -0.75])
    }

    @Test("a change of gain is spread over the buffer, so the volume does not click")
    func ramps() {
        // four frames of constant 1.0, from 0 to 1: 0, ¼, ½, ¾ (the last step lands on the next buffer)
        let result = render([1, 1, 1, 1, 1, 1, 1, 1], current: 0, target: 1)

        #expect(result == [0, 0, 0.25, 0.25, 0.5, 0.5, 0.75, 0.75])
    }

    @Test("after a buffer the gain has arrived, so the next one is steady")
    func arrives() {
        let gain = GainState(0)
        gain.target = 1
        let source = Streams([(2, [1, 1, 1, 1])])
        let output = Streams([(2, [0, 0, 0, 0])])

        AppTap.render(input: source.list, inputStart: 0, output: output.list, gain: gain)

        #expect(gain.current == 1)
    }

    @Test("the microphone of the output device, which comes first in the aggregate, is skipped")
    func skipsTheDeviceInputStreams() {
        let mic: (channels: Int, samples: [Float]) = (1, [0.9, 0.9])

        let result = render([0.2, 0.4, 0.6, 0.8], inputStart: 1, before: [mic])

        #expect(result == [0.2, 0.4, 0.6, 0.8])
    }

    @Test("a mono output plays the average of left and right")
    func mixesDownToMono() {
        let result = render([0.4, 0.8, 0.0, 1.0], outputChannels: 1, current: 0.5, target: 0.5)

        #expect(result.count == 2)
        #expect(abs(result[0] - 0.3) < 1e-6)  // (0.4 + 0.8) / 2 * 0.5
        #expect(abs(result[1] - 0.25) < 1e-6)  // (0.0 + 1.0) / 2 * 0.5
    }

    @Test("a mono source feeds a mono output as it is")
    func monoToMono() {
        #expect(render([0.3, -0.6], channels: 1, outputChannels: 1) == [0.3, -0.6])
    }

    @Test("the channels the source lacks stay silent")
    func sourceWithFewerChannels() {
        // mono source, stereo output: only the first channel is filled
        let result = render([0.3, -0.6], channels: 1, outputChannels: 2)

        #expect(result == [0.3, 0, -0.6, 0])
    }

    @Test("nothing to play leaves the output silent, not full of whatever was in it")
    func silenceWithoutInput() {
        let output = Streams([(2, [7, 7, 7, 7])])
        let source = Streams([])

        AppTap.render(input: source.list, inputStart: 0, output: output.list, gain: GainState(1))

        #expect(output.samples() == [0, 0, 0, 0])
    }

    @Test("an output buffer longer than the input is silent past the end of the input")
    func shorterInput() {
        let source = Streams([(2, [0.5, 0.5])])  // one frame
        let output = Streams([(2, [7, 7, 7, 7])])  // two frames

        AppTap.render(input: source.list, inputStart: 0, output: output.list, gain: GainState(1))

        #expect(output.samples() == [0.5, 0.5, 0, 0])
    }
}
