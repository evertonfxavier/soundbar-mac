import Testing

/// The microphone the sounds are mixed with: the one the user picked, else the system's default.
@Suite("SoundboardRouting microphone choice")
struct SoundboardMicrophoneTests {
    private func device(
        _ uid: String, _ name: String, input: Bool = true, output: Bool = true
    )
        -> SoundboardRouting.Device
    {
        .init(uid: uid, name: name, hasInput: input, hasOutput: output)
    }

    private var devices: [SoundboardRouting.Device] {
        [
            device("builtin", "Microfone (MacBook Pro)", output: false),
            device("headset", "Studio Pro WHG03P"),
            device("BlackHole2ch_UID", "BlackHole 2ch"),
        ]
    }

    @Test("the microphone the user picked wins over the default")
    func preferredWins() {
        let mic = SoundboardRouting.microphone(
            preferredUID: "headset", defaultInputUID: "builtin", devices: devices)
        #expect(mic?.uid == "headset")
    }

    @Test("a picked microphone that was unplugged falls back to the default")
    func unpluggedFallsBack() {
        let mic = SoundboardRouting.microphone(
            preferredUID: "gone", defaultInputUID: "headset", devices: devices)
        #expect(mic?.uid == "headset")
    }

    @Test("BlackHole is never taken as the real microphone, even if it was the one picked")
    func neverBlackHole() {
        let mic = SoundboardRouting.microphone(
            preferredUID: "BlackHole2ch_UID", defaultInputUID: "BlackHole2ch_UID", devices: devices)
        #expect(mic?.uid == "builtin")
    }

    @Test("with nothing picked it is the default, as before")
    func nothingPicked() {
        #expect(
            SoundboardRouting.microphone(preferredUID: nil, defaultInputUID: "headset", devices: devices)?.uid
                == "headset")
    }

    @Test("the real microphones offered leave out BlackHole and the devices without input")
    func realMicrophones() {
        let list = devices + [device("speakers", "Alto-falantes", input: false)]
        #expect(SoundboardRouting.realMicrophones(in: list).map(\.uid) == ["builtin", "headset"])
    }
}
