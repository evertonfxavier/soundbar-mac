import Testing

@Suite("Call mute")
struct CallMuteTests {
    @Test("the audio thread sees whether the call is muted")
    func mixerReportsMute() {
        let mixer = VoiceMixer()
        #expect(!mixer.isCallMutedForRender())
        mixer.setCallMuted(true)
        #expect(mixer.isCallMutedForRender())
        mixer.setCallMuted(false)
        #expect(!mixer.isCallMutedForRender())
    }

    @Test("a muted call gets silence: neither the microphone nor the sounds")
    func mutedFeedIsSilent() {
        let mixer = VoiceMixer()
        mixer.trigger(TestAudio.clip(frames: 2, left: 0.5), gain: 1)
        mixer.setCallMuted(true)
        let input = TestStreams([(1, [0.25, 0.25])])
        let output = TestStreams([(2, [9, 9, 9, 9])])
        MicFeed.render(input: input.list, output: output.list, outputStart: 0, mixer: mixer)
        #expect(output.samples() == [0, 0, 0, 0])
    }

    @Test("muting does not stop the sounds from advancing: unmuted again, the call hears what is left")
    func soundsKeepAdvancingWhileMuted() {
        let mixer = VoiceMixer()
        mixer.trigger(TestAudio.clip(frames: 4, left: 0.5), gain: 1)
        let input = TestStreams([(1, [0, 0])])

        mixer.setCallMuted(true)
        let first = TestStreams([(2, [9, 9, 9, 9])])
        MicFeed.render(input: input.list, output: first.list, outputStart: 0, mixer: mixer)
        mixer.setCallMuted(false)
        let second = TestStreams([(2, [9, 9, 9, 9])])
        MicFeed.render(input: input.list, output: second.list, outputStart: 0, mixer: mixer)

        #expect(first.samples() == [0, 0, 0, 0])
        #expect(second.samples() == [0.5, 0.5, 0.5, 0.5])
        #expect(mixer.activeVoices == 0)
    }

    @Test("unmuted, nothing changes")
    func unmutedIsAsBefore() {
        let mixer = VoiceMixer()
        let input = TestStreams([(1, [0.25, 0.25])])
        let output = TestStreams([(2, [9, 9, 9, 9])])
        MicFeed.render(input: input.list, output: output.list, outputStart: 0, mixer: mixer)
        #expect(output.samples() == [0.25, 0.25, 0.25, 0.25])
    }
}
