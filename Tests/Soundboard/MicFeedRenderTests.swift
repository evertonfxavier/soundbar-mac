import Testing

/// What the IOProc of the feed does with the buffers of the aggregate device: the first input stream is the real
/// microphone; the virtual microphone's output stream starts after the real device's own output streams.
@Suite("MicFeed.render")
struct MicFeedRenderTests {
    private func run(
        input: TestStreams, output: TestStreams, outputStart: Int = 0, mixer: VoiceMixer = VoiceMixer()
    ) {
        MicFeed.render(input: input.list, output: output.list, outputStart: outputStart, mixer: mixer)
    }

    @Test("a mono microphone goes into both channels of the virtual one")
    func monoMicrophone() {
        let input = TestStreams([(1, [0.1, 0.2, 0.3])])
        let output = TestStreams([(2, [Float](repeating: 9, count: 6))])
        run(input: input, output: output)
        #expect(output.samples() == [0.1, 0.1, 0.2, 0.2, 0.3, 0.3])
    }

    @Test("a stereo microphone keeps its sides")
    func stereoMicrophone() {
        let input = TestStreams([(2, [0.1, -0.1, 0.2, -0.2])])
        let output = TestStreams([(2, [Float](repeating: 9, count: 4))])
        run(input: input, output: output)
        #expect(output.samples() == [0.1, -0.1, 0.2, -0.2])
    }

    @Test("the sounds are added to the microphone")
    func soundsOnTop() {
        let mixer = VoiceMixer()
        mixer.trigger(TestAudio.clip(frames: 2, left: 0.5), gain: 1)
        let input = TestStreams([(1, [0.25, 0.25])])
        let output = TestStreams([(2, [Float](repeating: 0, count: 4))])
        run(input: input, output: output, mixer: mixer)
        #expect(output.samples() == [0.75, 0.75, 0.75, 0.75])
    }

    @Test("the real device's own output streams are silenced and the virtual stream is the one written")
    func skipsTheRealDevicesOutput() {
        let input = TestStreams([(1, [0.5, 0.5])])
        let output = TestStreams([(2, [Float](repeating: 7, count: 4)), (2, [Float](repeating: 9, count: 4))])
        run(input: input, output: output, outputStart: 1)
        #expect(output.samples(0) == [0, 0, 0, 0])
        #expect(output.samples(1) == [0.5, 0.5, 0.5, 0.5])
    }

    @Test("on a virtual device with many channels only the first two are written")
    func manyChannels() {
        let input = TestStreams([(1, [0.5])])
        let output = TestStreams([(4, [9, 9, 9, 9])])
        run(input: input, output: output)
        #expect(output.samples() == [0.5, 0.5, 0, 0])
    }

    @Test("a mono virtual device gets the left side")
    func monoVirtual() {
        let input = TestStreams([(2, [0.4, 0.8])])
        let output = TestStreams([(1, [9])])
        run(input: input, output: output)
        #expect(output.samples() == [0.4])
    }

    @Test("with no microphone data there is silence, and the sounds still play")
    func noInput() {
        let mixer = VoiceMixer()
        mixer.trigger(TestAudio.clip(frames: 1, left: 0.5), gain: 1)
        let output = TestStreams([(2, [9, 9])])
        run(input: TestStreams([]), output: output, mixer: mixer)
        #expect(output.samples() == [0.5, 0.5])
    }

    @Test("a short input leaves the rest of the block silent")
    func shortInput() {
        let input = TestStreams([(1, [0.5])])
        let output = TestStreams([(2, [9, 9, 9, 9])])
        run(input: input, output: output)
        #expect(output.samples() == [0.5, 0.5, 0, 0])
    }

    @Test("a missing virtual stream is not a crash")
    func missingOutputStream() {
        let input = TestStreams([(1, [0.5])])
        let output = TestStreams([(2, [9, 9])])
        run(input: input, output: output, outputStart: 3)
        #expect(output.samples() == [0, 0])
    }
}
