import Testing

@Suite("VoiceMixer")
struct VoiceMixerTests {
    /// Renders one block of `frames` frames into a buffer that starts with `initial`.
    private func render(
        _ mixer: VoiceMixer, frames: Int, channels: Int = 2, initial: Float = 0
    ) -> [Float] {
        var buffer = [Float](repeating: initial, count: frames * channels)
        buffer.withUnsafeMutableBufferPointer {
            mixer.render(into: $0.baseAddress!, frames: frames, channels: channels)
        }
        return buffer
    }

    @Test("a sound is added to the buffer, scaled by its gain")
    func addsWithGain() {
        let mixer = VoiceMixer()
        mixer.trigger(TestAudio.clip(frames: 4, left: 0.5), gain: 0.5)
        #expect(render(mixer, frames: 4) == [Float](repeating: 0.25, count: 8))
    }

    @Test("it is added to what the buffer already holds (the microphone), not put in its place")
    func addsToTheMicrophone() {
        let mixer = VoiceMixer()
        mixer.trigger(TestAudio.clip(frames: 2, left: 0.5), gain: 1)
        #expect(render(mixer, frames: 2, initial: 0.25) == [Float](repeating: 0.75, count: 4))
    }

    @Test("the sum is limited to full scale, on both sides")
    func limitedToFullScale() {
        let mixer = VoiceMixer()
        mixer.trigger(TestAudio.clip(frames: 2, left: 0.9, right: -0.9), gain: 1)
        let out = render(mixer, frames: 2, initial: 0.5)
        #expect(out[0] == 1 && out[2] == 1)
        #expect(abs(out[1] + 0.4) < 1e-6 && abs(out[3] + 0.4) < 1e-6)
    }

    @Test("a sound that is longer than a block goes on in the next one, then ends and is forgotten")
    func spansBlocks() {
        let mixer = VoiceMixer()
        mixer.trigger(TestAudio.clip(frames: 6, left: 1), gain: 1)
        #expect(render(mixer, frames: 4, channels: 1) == [1, 1, 1, 1])
        #expect(mixer.activeVoices == 1)
        #expect(render(mixer, frames: 4, channels: 1) == [1, 1, 0, 0])
        #expect(mixer.activeVoices == 0)
        #expect(render(mixer, frames: 4, channels: 1) == [0, 0, 0, 0])
    }

    @Test("two sounds at once are summed")
    func sumsVoices() {
        let mixer = VoiceMixer()
        mixer.trigger(TestAudio.clip(frames: 2, left: 0.25), gain: 1)
        mixer.trigger(TestAudio.clip(frames: 2, left: 0.5), gain: 1)
        #expect(render(mixer, frames: 2) == [Float](repeating: 0.75, count: 4))
    }

    @Test("a mono buffer gets the average of left and right")
    func monoBuffer() {
        let mixer = VoiceMixer()
        mixer.trigger(TestAudio.clip(frames: 2, left: 1, right: 0), gain: 1)
        #expect(render(mixer, frames: 2, channels: 1) == [0.5, 0.5])
    }

    @Test("with more than two channels only the first two are touched")
    func extraChannelsAreLeftAlone() {
        let mixer = VoiceMixer()
        mixer.trigger(TestAudio.clip(frames: 1, left: 0.5, right: 0.25), gain: 1)
        #expect(render(mixer, frames: 1, channels: 4, initial: 0.1) == [0.6, 0.35, 0.1, 0.1])
    }

    @Test("stopping silences everything that was playing")
    func stopAll() {
        let mixer = VoiceMixer()
        mixer.trigger(TestAudio.clip(frames: 8, left: 1), gain: 1)
        mixer.stopAll()
        #expect(mixer.activeVoices == 0)
        #expect(render(mixer, frames: 4) == [Float](repeating: 0, count: 8))
    }

    @Test("an empty clip is ignored")
    func emptyClip() {
        let mixer = VoiceMixer()
        mixer.trigger(SoundClip(samples: []), gain: 1)
        #expect(mixer.activeVoices == 0)
    }

    @Test("past the limit of voices the oldest one is cut")
    func voiceLimit() {
        let mixer = VoiceMixer()
        for _ in 0..<(VoiceMixer.maxVoices + 5) { mixer.trigger(TestAudio.clip(frames: 4, left: 0.01), gain: 1) }
        #expect(mixer.activeVoices == VoiceMixer.maxVoices)
    }

    @Test("an empty block, or no channels, is not an error")
    func degenerateBlocks() {
        let mixer = VoiceMixer()
        mixer.trigger(TestAudio.clip(frames: 4, left: 1), gain: 1)
        #expect(render(mixer, frames: 0).isEmpty)
        #expect(render(mixer, frames: 4, channels: 0).isEmpty)
        #expect(mixer.activeVoices == 1)
    }
}
